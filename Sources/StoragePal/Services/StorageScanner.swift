import Foundation

actor StorageScanner {
    private let fileManager = FileManager.default
    private let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
        .isUbiquitousItemKey
    ]

    func scan(progress: @escaping @Sendable (String) async -> Void) async -> ScanReport {
        await progress("Checking your Mac")
        let disks = mountedDisks()
        let locations = scanLocations()

        struct LocationScanResult {
            let folder: FolderSnapshot
            let largeFiles: [FileCandidate]
            let wasSkipped: Bool
            let locationURL: URL
        }

        let keys = resourceKeys
        let locationResults = await withTaskGroup(of: LocationScanResult?.self, returning: [LocationScanResult].self) { group in
            for location in locations {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let result = StorageScanner.measureLocation(location.url, resourceKeys: keys)
                    let folder = FolderSnapshot(
                        id: location.kind.rawValue,
                        name: location.name,
                        url: location.url,
                        bytes: result.bytes,
                        fileCount: result.fileCount,
                        kind: location.kind
                    )
                    return LocationScanResult(
                        folder: folder,
                        largeFiles: result.largeFiles,
                        wasSkipped: result.wasSkipped,
                        locationURL: location.url
                    )
                }
            }

            var collected: [LocationScanResult] = []
            for await res in group {
                guard let res else { continue }
                collected.append(res)
                await progress("Looking through \(res.folder.name)")
            }
            return collected
        }

        // Maintain original scan location order for consistent presentation
        var folders: [FolderSnapshot] = []
        var allLargeFiles: [FileCandidate] = []
        var skippedLocations: [URL] = []

        let resultsByKind = Dictionary(grouping: locationResults, by: { $0.folder.kind })
        for location in locations {
            if let match = resultsByKind[location.kind]?.first {
                folders.append(match.folder)
                allLargeFiles.append(contentsOf: match.largeFiles)
                if match.wasSkipped { skippedLocations.append(match.locationURL) }
            }
        }

        let largestFiles = Array(
            allLargeFiles
                .sorted { $0.bytes > $1.bytes }
                .prefix(80)
        )

        await progress("Scanning developer & creative caches")
        let devScanner = DeveloperScanner()
        let devResult = await devScanner.scan()

        await progress("Analyzing browser caches & system logs")
        let browserService = BrowserCleanerService()
        let browserGroups = await browserService.scanBrowserCaches()
        let logService = SystemLogCleanerService()
        let logGroups = await logService.scanStaleLogs()

        await progress("Preparing a short tidy list")
        let recommendations = buildRecommendations(
            folders: folders,
            largestFiles: largestFiles,
            externalDisks: disks.filter { !$0.isInternal },
            devResult: devResult,
            browserGroups: browserGroups,
            logGroups: logGroups
        )

        return ScanReport(
            createdAt: Date(),
            disks: disks,
            folders: folders,
            largestFiles: largestFiles,
            recommendations: recommendations,
            skippedLocations: skippedLocations
        )
    }

    private func mountedDisks() -> [DiskSnapshot] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey
        ]
        let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? [URL(fileURLWithPath: "/")]

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity,
                  total > 0 else { return nil }
            return DiskSnapshot(
                id: url.path,
                name: values.volumeName ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent),
                path: url,
                totalBytes: Int64(total),
                availableBytes: values.volumeAvailableCapacityForImportantUsage ?? 0,
                isInternal: values.volumeIsInternal ?? (url.path == "/"),
                isRemovable: values.volumeIsRemovable ?? false
            )
        }
        .sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func scanLocations() -> [(name: String, url: URL, kind: FolderKind)] {
        let home = fileManager.homeDirectoryForCurrentUser
        var locations: [(String, URL, FolderKind)] = [
            ("Desktop", home.appendingPathComponent("Desktop"), .desktop),
            ("Downloads", home.appendingPathComponent("Downloads"), .downloads),
            ("Documents", home.appendingPathComponent("Documents"), .documents),
            ("Movies", home.appendingPathComponent("Movies"), .movies),
            ("Pictures", home.appendingPathComponent("Pictures"), .pictures),
            ("Music", home.appendingPathComponent("Music"), .music),
            ("Trash", home.appendingPathComponent(".Trash"), .trash),
            ("App caches", home.appendingPathComponent("Library/Caches"), .caches)
        ]

        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fileManager.fileExists(atPath: iCloud.path) {
            locations.append(("iCloud Drive", iCloud, .iCloud))
        }
        return locations
    }

    private nonisolated static func measureLocation(_ root: URL, resourceKeys: Set<URLResourceKey>) -> (bytes: Int64, fileCount: Int, largeFiles: [FileCandidate], wasSkipped: Bool) {
        let fm = FileManager()
        guard fm.fileExists(atPath: root.path) else { return (0, 0, [], false) }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return (0, 0, [], true) }

        var bytes: Int64 = 0
        var fileCount = 0
        var largeFiles: [FileCandidate] = []
        var hadError = false

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            do {
                let values = try fileURL.resourceValues(forKeys: resourceKeys)
                if values.isSymbolicLink == true { continue }
                guard values.isRegularFile == true else { continue }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                bytes += size
                fileCount += 1
                if size >= 100_000_000 {
                    largeFiles.append(
                        FileCandidate(
                            id: fileURL.path,
                            url: fileURL,
                            bytes: size,
                            modifiedAt: values.contentModificationDate,
                            isCloudItem: values.isUbiquitousItem ?? false
                        )
                    )
                }
            } catch {
                hadError = true
            }
        }
        return (bytes, fileCount, largeFiles, hadError)
    }

    private func buildRecommendations(
        folders: [FolderSnapshot],
        largestFiles: [FileCandidate],
        externalDisks: [DiskSnapshot],
        devResult: DeveloperScanResult,
        browserGroups: [BrowserCacheGroup] = [],
        logGroups: [SystemLogGroup] = []
    ) -> [StorageRecommendation] {
        var items: [StorageRecommendation] = []
        let now = Date()

        if let trash = folders.first(where: { $0.kind == .trash }), trash.bytes > 100_000_000 {
            items.append(
                StorageRecommendation(
                    id: "trash",
                    kind: .trash,
                    title: "Empty the Trash",
                    detail: "You’ve already decided these can go. macOS will ask you to confirm.",
                    reclaimableBytes: trash.bytes,
                    candidates: [],
                    actionLabel: "Open Trash"
                )
            )
        }

        if !browserGroups.isEmpty {
            let total = browserGroups.reduce(0) { $0 + $1.bytes }
            if total >= 10_000_000 {
                items.append(
                    StorageRecommendation(
                        id: "browser-caches",
                        kind: .browserCaches,
                        title: "Clean disposable browser caches",
                        detail: "Safely reclaim \(ByteText.string(total)) across Safari, Chrome, and Firefox without touching saved logins or cookies.",
                        reclaimableBytes: total,
                        candidates: [],
                        actionLabel: "Review caches"
                    )
                )
            }
        }

        if !logGroups.isEmpty {
            let total = logGroups.reduce(0) { $0 + $1.bytes }
            if total >= 5_000_000 {
                let candidates = logGroups.map {
                    FileCandidate(
                        id: $0.id,
                        url: $0.url,
                        bytes: $0.bytes,
                        modifiedAt: $0.oldestFileDate,
                        isCloudItem: false
                    )
                }
                items.append(
                    StorageRecommendation(
                        id: "stale-system-logs",
                        kind: .staleSystemLogs,
                        title: "Clean stale crash logs & diagnostics",
                        detail: "Clear old crash reports, diagnostics, and spin dumps older than 14 days.",
                        reclaimableBytes: total,
                        candidates: candidates,
                        actionLabel: "Review logs"
                    )
                )
            }
        }

        if !devResult.xcodeCandidates.isEmpty {
            let total = devResult.xcodeCandidates.reduce(0) { $0 + $1.bytes }
            items.append(
                StorageRecommendation(
                    id: "xcode-caches",
                    kind: .developerCaches,
                    title: "Clean Xcode DerivedData & Caches",
                    detail: "Safely clean intermediate Xcode build artifacts and simulator logs without touching source code.",
                    reclaimableBytes: total,
                    candidates: devResult.xcodeCandidates,
                    actionLabel: "Review caches"
                )
            )
        }

        if !devResult.projectArtifactCandidates.isEmpty {
            let total = devResult.projectArtifactCandidates.reduce(0) { $0 + $1.bytes }
            items.append(
                StorageRecommendation(
                    id: "stale-project-artifacts",
                    kind: .staleProjectArtifacts,
                    title: "Clean untouched project build files",
                    detail: "Found node_modules or build target folders in projects untouched for over 30 days.",
                    reclaimableBytes: total,
                    candidates: devResult.projectArtifactCandidates,
                    actionLabel: "Review projects"
                )
            )
        }

        if !devResult.creativeCacheCandidates.isEmpty {
            let total = devResult.creativeCacheCandidates.reduce(0) { $0 + $1.bytes }
            items.append(
                StorageRecommendation(
                    id: "creative-caches",
                    kind: .creativeCaches,
                    title: "Clean Adobe & Final Cut Pro render caches",
                    detail: "Media scratch files and render caches from video/audio editing software.",
                    reclaimableBytes: total,
                    candidates: devResult.creativeCacheCandidates,
                    actionLabel: "Review caches"
                )
            )
        }

        if !devResult.installerCandidates.isEmpty {
            let total = devResult.installerCandidates.reduce(0) { $0 + $1.bytes }
            items.append(
                StorageRecommendation(
                    id: "orphaned-installers",
                    kind: .orphanedInstallers,
                    title: "Clean installed DMG & PKG installers",
                    detail: "Installer files in Downloads/Desktop for applications already installed in Applications.",
                    reclaimableBytes: total,
                    candidates: devResult.installerCandidates,
                    actionLabel: "Review installers"
                )
            )
        }

        let oldDownloads = largestFiles.filter { file in
            file.url.path.contains("/Downloads/") &&
            (file.modifiedAt.map { now.timeIntervalSince($0) > 30 * 24 * 60 * 60 } ?? false)
        }
        if !oldDownloads.isEmpty {
            items.append(
                StorageRecommendation(
                    id: "old-downloads",
                    kind: .oldDownloads,
                    title: "Review old downloads",
                    detail: "Large downloads untouched for at least 30 days are often the easiest win.",
                    reclaimableBytes: oldDownloads.reduce(0) { $0 + $1.bytes },
                    candidates: oldDownloads,
                    actionLabel: "Review files"
                )
            )
        }

        let veryLargeFiles = Array(largestFiles.filter { $0.bytes >= 1_000_000_000 }.prefix(20))
        if !veryLargeFiles.isEmpty {
            items.append(
                StorageRecommendation(
                    id: "large-files",
                    kind: .largeFiles,
                    title: "Check the big stuff",
                    detail: "These are your largest accessible files. Keep, archive, or move each one to Trash.",
                    reclaimableBytes: veryLargeFiles.reduce(0) { $0 + $1.bytes },
                    candidates: veryLargeFiles,
                    actionLabel: "Review files"
                )
            )
        }

        if let desktop = folders.first(where: { $0.kind == .desktop }), desktop.fileCount > 20 {
            items.append(
                StorageRecommendation(
                    id: "desktop",
                    kind: .desktop,
                    title: "Calm the Desktop",
                    detail: "There are \(desktop.fileCount) items here. Open it with macOS Stacks ready to help.",
                    reclaimableBytes: 0,
                    candidates: [],
                    actionLabel: "Open Desktop"
                )
            )
        }

        if let iCloud = folders.first(where: { $0.kind == .iCloud }) {
            items.append(
                StorageRecommendation(
                    id: "icloud",
                    kind: .iCloud,
                    title: "Check iCloud storage",
                    detail: "Storage Pal can see \(ByteText.string(iCloud.bytes)) in your local iCloud Drive. Apple’s storage panel shows the full 50 GB account breakdown.",
                    reclaimableBytes: 0,
                    candidates: [],
                    actionLabel: "Manage iCloud"
                )
            )
        }

        if !externalDisks.isEmpty && !veryLargeFiles.isEmpty {
            items.append(
                StorageRecommendation(
                    id: "archive",
                    kind: .archive,
                    title: "Archive to an external drive",
                    detail: "Your archive drive is connected. Storage Pal can reveal a file and the drive side by side for a deliberate move.",
                    reclaimableBytes: 0,
                    candidates: Array(veryLargeFiles.prefix(10)),
                    actionLabel: "Choose a file"
                )
            )
        }

        return items.sorted {
            if $0.reclaimableBytes != $1.reclaimableBytes { return $0.reclaimableBytes > $1.reclaimableBytes }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }
}
