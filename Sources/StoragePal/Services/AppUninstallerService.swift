import Foundation

actor AppUninstallerService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    func scanInstalledApps() async -> [InstalledApp] {
        let appDirectories = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]

        var apps: [InstalledApp] = []
        for dir in appDirectories where fm.fileExists(atPath: dir.path) {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }

            for itemURL in contents where itemURL.pathExtension.lowercased() == "app" {
                if Task.isCancelled { break }
                let app = scanSingleApp(at: itemURL)
                apps.append(app)
            }
        }
        return apps.sorted { $0.totalReclaimableBytes > $1.totalReclaimableBytes }
    }

    private func scanSingleApp(at appURL: URL) -> InstalledApp {
        let name = appURL.deletingPathExtension().lastPathComponent
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        var bundleID: String? = nil

        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            bundleID = plist["CFBundleIdentifier"] as? String
        }

        let appSize = measureSize(appURL)
        let leftovers = findLeftovers(appName: name, bundleID: bundleID)

        return InstalledApp(
            id: appURL.path,
            name: name,
            bundleIdentifier: bundleID,
            appURL: appURL,
            appSizeBytes: appSize,
            leftovers: leftovers
        )
    }

    private func findLeftovers(appName: String, bundleID: String?) -> [InstalledAppLeftover] {
        var leftovers: [InstalledAppLeftover] = []
        let libraryLocations: [(category: String, path: String)] = [
            ("Application Support", "Library/Application Support"),
            ("Containers", "Library/Containers"),
            ("Group Containers", "Library/Group Containers"),
            ("Caches", "Library/Caches"),
            ("Preferences", "Library/Preferences"),
            ("Logs", "Library/Logs"),
            ("Saved State", "Library/Saved Application State"),
            ("LaunchAgents", "Library/LaunchAgents")
        ]

        let reservedNames: Set<String> = ["System", "Library", "Apple", "Common", "Preferences", "Caches", "Logs", "Containers", "Application Support", "Frameworks"]

        for (category, relPath) in libraryLocations {
            let baseDir = home.appendingPathComponent(relPath)
            guard fm.fileExists(atPath: baseDir.path) else { continue }

            if let bundleID, !bundleID.isEmpty {
                let directMatch = baseDir.appendingPathComponent(bundleID)
                if fm.fileExists(atPath: directMatch.path) {
                    let sz = measureSize(directMatch)
                    leftovers.append(InstalledAppLeftover(category: category, url: directMatch, bytes: sz))
                }
            }

            if appName.count >= 3 && !reservedNames.contains(appName) {
                let nameMatch = baseDir.appendingPathComponent(appName)
                if fm.fileExists(atPath: nameMatch.path) && !leftovers.contains(where: { $0.url == nameMatch }) {
                    let sz = measureSize(nameMatch)
                    leftovers.append(InstalledAppLeftover(category: category, url: nameMatch, bytes: sz))
                }
            }
        }
        return leftovers
    }

    private func measureSize(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
