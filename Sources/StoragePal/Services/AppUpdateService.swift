import AppKit
import Foundation
import Security

@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    @Published var status: UpdateCheckStatus = .idle
    @Published var isPresented: Bool = false

    @Published var lastCheckDate: Date? {
        didSet {
            UserDefaults.standard.set(lastCheckDate, forKey: "StoragePalLastUpdateCheckDate")
        }
    }

    @Published var automaticallyCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyCheckForUpdates, forKey: "StoragePalAutoUpdateCheck")
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.16.0"
    }

    private let fm = FileManager.default
    private let releaseFeedURL = URL(string: "https://api.github.com/repos/richchips/storagepal/releases/latest")

    init() {
        self.automaticallyCheckForUpdates = UserDefaults.standard.object(forKey: "StoragePalAutoUpdateCheck") as? Bool ?? true
        self.lastCheckDate = UserDefaults.standard.object(forKey: "StoragePalLastUpdateCheckDate") as? Date

        if automaticallyCheckForUpdates {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await checkForUpdates(userInitiated: false)
            }
        }
    }

    // MARK: - Version Comparison

    static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).components(separatedBy: ".")
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).components(separatedBy: ".")

        let maxCount = max(clean1.count, clean2.count)
        for i in 0..<maxCount {
            let num1 = i < clean1.count ? (Int(clean1[i]) ?? 0) : 0
            let num2 = i < clean2.count ? (Int(clean2[i]) ?? 0) : 0

            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }

    // MARK: - Check for Updates

    func checkForUpdates(userInitiated: Bool = false) async {
        if userInitiated {
            self.isPresented = true
        }
        status = .checking
        self.lastCheckDate = Date()

        guard let feedURL = releaseFeedURL else {
            status = .failed("Invalid release feed URL.")
            return
        }

        var request = URLRequest(url: feedURL)
        request.setValue("StoragePal/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                status = .failed("Invalid response from update server.")
                return
            }

            if httpResponse.statusCode == 200 {
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    status = .failed("Could not parse release payload from GitHub.")
                    return
                }

                let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let body = json["body"] as? String ?? "Performance improvements, clinical de-identification upgrades, and single-auth batch cleaning."
                let publishedAt = (json["published_at"] as? String)?.prefix(10) ?? "Recently"

                var downloadURL = "https://github.com/richchips/storagepal/releases/latest"
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, (name.hasSuffix(".zip") || name.contains("Storage")),
                           let browserURL = asset["browser_download_url"] as? String {
                            downloadURL = browserURL
                            break
                        }
                    }
                }

                let releaseInfo = AppReleaseInfo(
                    version: remoteVersion,
                    releaseDate: String(publishedAt),
                    releaseNotes: body,
                    downloadURL: downloadURL,
                    sha256: nil,
                    minimumMacOSVersion: "14.0"
                )

                if Self.isVersion(remoteVersion, greaterThan: currentVersion) {
                    status = .updateAvailable(releaseInfo)
                    self.isPresented = true
                } else {
                    status = .upToDate(currentVersion: currentVersion)
                }
            } else if httpResponse.statusCode == 404 {
                status = .failed("No public release found for Storage Pal.")
            } else if httpResponse.statusCode == 403 {
                status = .failed("GitHub API rate limit exceeded or access forbidden.")
            } else {
                status = .failed("Update server returned HTTP status \(httpResponse.statusCode).")
            }
        } catch {
            status = .failed("Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Fast Download and Staging

    func downloadAndInstallUpdate(release: AppReleaseInfo) async throws {
        status = .downloading(progress: 0.15)

        let tempDir = fm.temporaryDirectory.appendingPathComponent("StoragePalUpdate_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let zipURL = tempDir.appendingPathComponent("StoragePal.zip")

        // Prefer remote download from GitHub release asset
        if let remoteURL = URL(string: release.downloadURL), remoteURL.scheme != nil {
            status = .downloading(progress: 0.35)
            let (downloadedURL, response) = try await URLSession.shared.download(from: remoteURL)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                status = .failed("Download failed with HTTP status \(httpResp.statusCode).")
                return
            }
            status = .downloading(progress: 0.70)
            try? fm.removeItem(at: zipURL)
            try fm.moveItem(at: downloadedURL, to: zipURL)
        } else {
            // Local fallback archive if present
            let localDistZip = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Storage Pal.zip")
            if fm.fileExists(atPath: localDistZip.path) {
                try? fm.copyItem(at: localDistZip, to: zipURL)
            }
        }

        status = .downloading(progress: 0.85)

        // Unpack archive using ditto
        let stagedAppDir = tempDir.appendingPathComponent("Extracted")
        try fm.createDirectory(at: stagedAppDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, stagedAppDir.path]
        try process.run()
        process.waitUntilExit()

        status = .downloading(progress: 0.95)

        // Find .app bundle inside extracted directory
        let extractedItems = (try? fm.contentsOfDirectory(at: stagedAppDir, includingPropertiesForKeys: nil)) ?? []
        guard let stagedAppURL = extractedItems.first(where: { $0.pathExtension == "app" }) else {
            status = .failed("No .app bundle was found in the downloaded archive.")
            return
        }

        // Clean extended attributes on the extracted bundle
        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-cr", stagedAppURL.path]
        try? xattrProcess.run()
        xattrProcess.waitUntilExit()

        status = .readyToRelaunch(stagedURL: stagedAppURL)
    }

    // MARK: - Reliable PID-Aware Relaunch

    func relaunchApp(stagedAppURL: URL) {
        let currentAppURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let tempDir = stagedAppURL.deletingLastPathComponent()

        let script = """
        #!/bin/sh
        exec > "/tmp/storagepal_updater.log" 2>&1
        echo "=== Storage Pal Updater Started at $(date) ==="
        echo "Old PID: \(pid)"
        echo "Current App: \(currentAppURL.path)"
        echo "Staged App: \(stagedAppURL.path)"

        # Wait for the currently running app PID to cleanly terminate (up to 4s)
        WAITED=0
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.1
            WAITED=$((WAITED + 1))
            if [ $WAITED -ge 40 ]; then
                echo "Process still running after 4s, sending SIGKILL..."
                kill -9 \(pid) 2>/dev/null || true
                break
            fi
        done
        sleep 0.2

        echo "Swapping application bundle..."
        rm -rf "\(currentAppURL.path)"
        /usr/bin/ditto "\(stagedAppURL.path)" "\(currentAppURL.path)"
        /usr/bin/xattr -cr "\(currentAppURL.path)" 2>/dev/null || true
        /bin/chmod -R 755 "\(currentAppURL.path)" 2>/dev/null || true

        echo "Relaunching updated app..."
        /usr/bin/open "\(currentAppURL.path)"
        echo "Update complete!"

        # Clean up temporary staging directory
        rm -rf "\(tempDir.path)"
        """

        let tempScript = fm.temporaryDirectory.appendingPathComponent("relaunch_\(UUID().uuidString).sh")
        try? script.write(to: tempScript, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        // Launch detached process so it survives application termination
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "nohup /bin/sh '\(tempScript.path)' >/tmp/storagepal_updater.log 2>&1 &"]
        try? task.run()

        // Force immediate exit so the updater script can swap and relaunch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            exit(0)
        }
    }
}
