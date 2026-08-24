import Foundation

struct DeveloperScanResult: Sendable {
    var xcodeCandidates: [FileCandidate]
    var projectArtifactCandidates: [FileCandidate]
    var creativeCacheCandidates: [FileCandidate]
    var installerCandidates: [FileCandidate]

    var totalBytes: Int64 {
        let xcode = xcodeCandidates.reduce(0) { $0 + $1.bytes }
        let project = projectArtifactCandidates.reduce(0) { $0 + $1.bytes }
        let creative = creativeCacheCandidates.reduce(0) { $0 + $1.bytes }
        let installer = installerCandidates.reduce(0) { $0 + $1.bytes }
        return xcode + project + creative + installer
    }
}

actor DeveloperScanner {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    func scan() async -> DeveloperScanResult {
        async let xcode = scanXcodeCaches()
        async let projects = scanStaleProjectArtifacts()
        async let creative = scanCreativeCaches()
        async let installers = scanOrphanedInstallers()

        let (x, p, c, i) = await (xcode, projects, creative, installers)
        return DeveloperScanResult(
            xcodeCandidates: x,
            projectArtifactCandidates: p,
            creativeCacheCandidates: c,
            installerCandidates: i
        )
    }

    private func scanXcodeCaches() -> [FileCandidate] {
        var candidates: [FileCandidate] = []
        let xcodeLocations = [
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            home.appendingPathComponent("Library/Developer/Xcode/Archives"),
            home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceLogs"),
            home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
            home.appendingPathComponent("Library/Logs/CoreSimulator")
        ]

        for location in xcodeLocations where fm.fileExists(atPath: location.path) {
            guard let contents = try? fm.contentsOfDirectory(at: location, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }

            for itemURL in contents {
                let size = measureFolderOrFileSize(itemURL)
                guard size >= 20_000_000 else { continue } // >= 20 MB

                let modDate = (try? itemURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                candidates.append(
                    FileCandidate(
                        id: itemURL.path,
                        url: itemURL,
                        bytes: size,
                        modifiedAt: modDate,
                        isCloudItem: false
                    )
                )
            }
        }
        return candidates.sorted { $0.bytes > $1.bytes }
    }

    private func scanStaleProjectArtifacts() -> [FileCandidate] {
        var candidates: [FileCandidate] = []
        let searchRoots = [
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Documents")
        ]

        let cutoffDate = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days untouched
        let targetFolderNames = ["node_modules", "target", ".venv", "venv", ".build"]

        for root in searchRoots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else { continue }

            while let folderURL = enumerator.nextObject() as? URL {
                guard targetFolderNames.contains(folderURL.lastPathComponent) else { continue }
                enumerator.skipDescendants()

                let modDate = (try? folderURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modDate, modDate > cutoffDate { continue }

                let size = measureFolderOrFileSize(folderURL)
                guard size >= 30_000_000 else { continue } // >= 30 MB

                candidates.append(
                    FileCandidate(
                        id: folderURL.path,
                        url: folderURL,
                        bytes: size,
                        modifiedAt: modDate,
                        isCloudItem: false
                    )
                )
            }
        }
        return candidates.sorted { $0.bytes > $1.bytes }
    }

    private func scanCreativeCaches() -> [FileCandidate] {
        var candidates: [FileCandidate] = []
        let creativeLocations = [
            home.appendingPathComponent("Library/Caches/Adobe"),
            home.appendingPathComponent("Library/Caches/com.apple.FinalCut"),
            home.appendingPathComponent("Library/Application Support/Adobe/Common/Media Cache Files")
        ]

        for location in creativeLocations where fm.fileExists(atPath: location.path) {
            let size = measureFolderOrFileSize(location)
            guard size >= 50_000_000 else { continue }

            let modDate = (try? location.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            candidates.append(
                FileCandidate(
                    id: location.path,
                    url: location,
                    bytes: size,
                    modifiedAt: modDate,
                    isCloudItem: false
                )
            )
        }
        return candidates
    }

    private func scanOrphanedInstallers() -> [FileCandidate] {
        var candidates: [FileCandidate] = []
        let installerRoots = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop")
        ]
        let installerExtensions = ["dmg", "pkg", "iso"]

        let applicationsDir = URL(fileURLWithPath: "/Applications")
        let installedApps = (try? fm.contentsOfDirectory(at: applicationsDir, includingPropertiesForKeys: nil).map { $0.deletingPathExtension().lastPathComponent.lowercased() }) ?? []

        for root in installerRoots where fm.fileExists(atPath: root.path) {
            guard let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }

            for fileURL in contents where installerExtensions.contains(fileURL.pathExtension.lowercased()) {
                let size = Int64((try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                guard size >= 20_000_000 else { continue }

                let nameLower = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                let isOrphaned = installedApps.contains { installed in
                    nameLower.contains(installed) || installed.contains(nameLower)
                }

                if isOrphaned {
                    let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    candidates.append(
                        FileCandidate(
                            id: fileURL.path,
                            url: fileURL,
                            bytes: size,
                            modifiedAt: modDate,
                            isCloudItem: false
                        )
                    )
                }
            }
        }
        return candidates.sorted { $0.bytes > $1.bytes }
    }

    private func measureFolderOrFileSize(_ url: URL) -> Int64 {
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
