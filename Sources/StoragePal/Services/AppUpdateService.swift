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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.15.0"
    }

    private let fm = FileManager.default
    private let releaseFeedURL = URL(string: "https://api.github.com/repos/richchips/storagepal/releases/latest")

    init() {
        self.automaticallyCheckForUpdates = UserDefaults.standard.object(forKey: "StoragePalAutoUpdateCheck") as? Bool ?? true
        self.lastCheckDate = UserDefaults.standard.object(forKey: "StoragePalLastUpdateCheckDate") as? Date

        if automaticallyCheckForUpdates {
            Task {
                // Check in background after app startup
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
                let body = json["body"] as? String ?? "Performance improvements and bug fixes."
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
                status = .failed("GitHub repository 'richchips/storagepal' is set to Private. Unauthenticated update checks cannot access private releases. Make the repository Public on GitHub to allow in-app updates.")
            } else if httpResponse.statusCode == 403 {
                status = .failed("GitHub API rate limit exceeded or access forbidden (HTTP 403).")
            } else {
                status = .failed("Update server returned HTTP status \(httpResponse.statusCode).")
            }
        } catch {
            status = .failed("Network connection error: \(error.localizedDescription)")
        }
    }

    // MARK: - Download and Install

    func downloadAndInstallUpdate(release: AppReleaseInfo) async throws {
        status = .downloading(progress: 0.1)

        let tempDir = fm.temporaryDirectory.appendingPathComponent("StoragePalUpdate_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let zipURL = tempDir.appendingPathComponent("StoragePal.zip")

        // Progress simulation during download
        for p in [0.2, 0.4, 0.7, 0.9] {
            try? await Task.sleep(nanoseconds: 300_000_000)
            status = .downloading(progress: p)
        }

        // If local dist package exists (for testing/distribution), stage it directly
        let localDistZip = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Storage Pal.zip")
        let sourceZipURL: URL
        if fm.fileExists(atPath: localDistZip.path) {
            sourceZipURL = localDistZip
        } else if let remoteURL = URL(string: release.downloadURL), remoteURL.scheme != nil {
            let (downloadedURL, _) = try await URLSession.shared.download(from: remoteURL)
            try? fm.removeItem(at: zipURL)
            try fm.moveItem(at: downloadedURL, to: zipURL)
            sourceZipURL = zipURL
        } else {
            sourceZipURL = zipURL
        }

        // Unzip staged archive
        let stagedAppDir = tempDir.appendingPathComponent("Extracted")
        try fm.createDirectory(at: stagedAppDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", sourceZipURL.path, stagedAppDir.path]
        try process.run()
        process.waitUntilExit()

        let stagedAppURL = stagedAppDir.appendingPathComponent("StoragePal.app")
        status = .readyToRelaunch(stagedURL: stagedAppURL)
    }

    // MARK: - Relaunch Application

    func relaunchApp(stagedAppURL: URL) {
        let currentAppURL = Bundle.main.bundleURL

        let script = """
        sleep 0.5
        rm -rf "\(currentAppURL.path)"
        cp -R "\(stagedAppURL.path)" "\(currentAppURL.path)"
        open "\(currentAppURL.path)"
        """

        let tempScript = fm.temporaryDirectory.appendingPathComponent("relaunch_\(UUID().uuidString).sh")
        try? script.write(to: tempScript, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [tempScript.path]
        try? task.run()

        NSApplication.shared.terminate(nil)
    }
}
