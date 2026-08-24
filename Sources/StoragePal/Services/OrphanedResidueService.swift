import Foundation

actor OrphanedResidueService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private let reservedPrefixes: Set<String> = [
        "com.apple.", "apple.", "system.", "org.swift.", "com.google.keystone"
    ]

    private let reservedNames: Set<String> = [
        "Apple", "System", "CloudDocs", "Mobile Documents", "QuickLook", "Automator",
        "Safari", "Finder", "Dock", "Preferences", "Keychains", "Accounts", "AddressBook",
        "CallHistoryDB", "Messages", "Mail", "Photos", "Passes", "Reminders", "Calendar",
        "Notes", "ContextStoreSubsystem", "Suggestions", "CoreData", "CrashReporter",
        "IdentityServices", "FeedbackAssistant", "Assistant", "Spotlight", "Bluetooth",
        "Audio", "FontCollections", "Fonts", "ColorPickers", "ColorSync", "Services",
        "Sounds", "Screen Savers", "PreferencePanes", "Input Methods", "Keyboard Layouts",
        "VoiceTrigger", "Biome", "Knowledge", "Metadata", "Containers", "Application Support",
        "Group Containers", "Caches", "Logs", "Saved Application State", "WebKit", "Google"
    ]

    init() {}

    /// Scans for residual support folders left behind by previously uninstalled apps.
    func scanOrphanedResidues() async -> [OrphanedAppResidue] {
        let installedAppInfo = await gatherInstalledAppIdentifiers()

        let searchLocations: [(category: String, path: String)] = [
            ("Application Support", "Library/Application Support"),
            ("Containers", "Library/Containers"),
            ("Group Containers", "Library/Group Containers"),
            ("Caches", "Library/Caches"),
            ("Preferences", "Library/Preferences"),
            ("Saved Application State", "Library/Saved Application State")
        ]

        var residues: [OrphanedAppResidue] = []

        for (category, relPath) in searchLocations {
            if Task.isCancelled { break }
            let baseDir = home.appendingPathComponent(relPath)
            guard fm.fileExists(atPath: baseDir.path) else { continue }

            guard let entries = try? fm.contentsOfDirectory(
                at: baseDir,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for itemURL in entries {
                if Task.isCancelled { break }
                let itemName = itemURL.lastPathComponent

                // Filter out Apple, system, and reserved folders
                if isReserved(itemName: itemName) { continue }

                // Check if this matches any installed app
                let matchesInstalled = isMatchedToInstalledApp(
                    nameOrBundle: itemName,
                    installedNames: installedAppInfo.names,
                    installedBundles: installedAppInfo.bundleIDs
                )

                if !matchesInstalled {
                    let sz = measureSize(itemURL)
                    // Only include orphaned folders that actually occupy space (> 100 KB)
                    if sz >= 100_000 {
                        let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey])
                        residues.append(
                            OrphanedAppResidue(
                                name: formatDisplayName(for: itemName),
                                bundleIdentifier: itemName.contains(".") ? itemName : nil,
                                category: category,
                                url: itemURL,
                                bytes: sz,
                                lastModified: values?.contentModificationDate
                            )
                        )
                    }
                }
            }
        }

        return residues.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Private Helpers

    private func gatherInstalledAppIdentifiers() async -> (names: Set<String>, bundleIDs: Set<String>) {
        var names = Set<String>()
        var bundleIDs = Set<String>()

        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications")
        ]

        for dir in appDirs where fm.fileExists(atPath: dir.path) {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }

            for item in contents where item.pathExtension.lowercased() == "app" {
                let appName = item.deletingPathExtension().lastPathComponent
                names.insert(appName.lowercased())

                let plistURL = item.appendingPathComponent("Contents/Info.plist")
                if let data = try? Data(contentsOf: plistURL),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let bid = plist["CFBundleIdentifier"] as? String {
                    bundleIDs.insert(bid.lowercased())
                }
            }
        }

        return (names, bundleIDs)
    }

    private func isReserved(itemName: String) -> Bool {
        if reservedNames.contains(itemName) { return true }
        let lower = itemName.lowercased()
        for prefix in reservedPrefixes where lower.hasPrefix(prefix) {
            return true
        }
        return false
    }

    private func isMatchedToInstalledApp(nameOrBundle: String, installedNames: Set<String>, installedBundles: Set<String>) -> Bool {
        let lower = nameOrBundle.lowercased()

        if installedBundles.contains(lower) { return true }
        if installedNames.contains(lower) { return true }

        // Check substring containment for bundle identifiers (e.g., com.spotify.client vs spotify)
        for name in installedNames where name.count >= 4 {
            if lower.contains(name) { return true }
        }

        for bid in installedBundles where bid.count >= 6 {
            if lower.contains(bid) || bid.contains(lower) { return true }
        }

        return false
    }

    private func formatDisplayName(for rawName: String) -> String {
        var cleaned = rawName
        if cleaned.hasSuffix(".savedState") {
            cleaned = String(cleaned.dropLast(11))
        }
        // Extract meaningful stem from reverse domain notation (e.g. com.tinyspeck.slackmacgap -> Slack)
        if cleaned.contains(".") {
            let parts = cleaned.split(separator: ".")
            if let last = parts.last, last.count > 2 {
                return String(last).capitalized
            }
        }
        return cleaned
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
