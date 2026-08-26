import Foundation

actor QuickCleanService {
    public static let shared = QuickCleanService()

    private let browserCleaner = BrowserCleanerService()
    private let logCleaner = SystemLogCleanerService()
    private let devScanner = DeveloperScanner()
    private let orphanedService = OrphanedResidueService()
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    public init() {}

    /// Performs a high-speed parallel scan across all low-risk, disposable clutter locations.
    public func scanQuickCleanTargets(progress: (@Sendable (String) async -> Void)? = nil) async -> QuickCleanScanResult {
        var items: [QuickCleanItem] = []

        await progress?("Scanning disposable browser caches…")
        let browserGroups = await browserCleaner.scanBrowserCaches()
        for group in browserGroups {
            items.append(
                QuickCleanItem(
                    id: "browser-\(group.id)",
                    name: "\(group.browser.rawValue) Web Cache",
                    url: group.cacheURL,
                    bytes: group.bytes,
                    category: .browserCaches,
                    detail: "\(group.fileCount) cached files & media buffers",
                    isSafeByDefault: true
                )
            )
        }

        if Task.isCancelled { return QuickCleanScanResult(items: items) }

        await progress?("Scanning stale diagnostic & crash logs…")
        let logGroups = await logCleaner.scanStaleLogs(olderThanDays: 14)
        for group in logGroups {
            items.append(
                QuickCleanItem(
                    id: "log-\(group.id)",
                    name: group.name,
                    url: group.url,
                    bytes: group.bytes,
                    category: .systemLogs,
                    detail: "\(group.fileCount) stale crash/diagnostic files (>14 days)",
                    isSafeByDefault: true
                )
            )
        }

        if Task.isCancelled { return QuickCleanScanResult(items: items) }

        await progress?("Scanning developer & build caches…")
        let devResult = await devScanner.scan()
        for candidate in devResult.xcodeCandidates {
            items.append(
                QuickCleanItem(
                    id: "xcode-\(candidate.id)",
                    name: candidate.name,
                    url: candidate.url,
                    bytes: candidate.bytes,
                    category: .developerCaches,
                    detail: "Xcode DerivedData & temporary build files",
                    isSafeByDefault: true
                )
            )
        }

        for candidate in devResult.installerCandidates {
            items.append(
                QuickCleanItem(
                    id: "installer-\(candidate.id)",
                    name: candidate.name,
                    url: candidate.url,
                    bytes: candidate.bytes,
                    category: .orphanedInstallers,
                    detail: "Installer already present in /Applications",
                    isSafeByDefault: true
                )
            )
        }

        for candidate in devResult.projectArtifactCandidates {
            items.append(
                QuickCleanItem(
                    id: "project-\(candidate.id)",
                    name: candidate.name,
                    url: candidate.url,
                    bytes: candidate.bytes,
                    category: .staleProjectArtifacts,
                    detail: "Untouched dependency / build directory (>30 days)",
                    isSafeByDefault: true
                )
            )
        }

        for candidate in devResult.creativeCacheCandidates {
            items.append(
                QuickCleanItem(
                    id: "creative-\(candidate.id)",
                    name: candidate.name,
                    url: candidate.url,
                    bytes: candidate.bytes,
                    category: .developerCaches,
                    detail: "Creative app scratch & media cache",
                    isSafeByDefault: true
                )
            )
        }

        if Task.isCancelled { return QuickCleanScanResult(items: items) }

        await progress?("Checking orphaned app leftovers…")
        let residues = await orphanedService.scanOrphanedResidues()
        for residue in residues {
            items.append(
                QuickCleanItem(
                    id: "residue-\(residue.id)",
                    name: residue.name,
                    url: residue.url,
                    bytes: residue.bytes,
                    category: .orphanedResidue,
                    detail: "Ghost \(residue.category) for deleted application",
                    isSafeByDefault: true
                )
            )
        }

        // Check user Trash
        let trashURL = home.appendingPathComponent(".Trash")
        if fm.fileExists(atPath: trashURL.path) {
            let (trashBytes, trashCount) = measureDirectory(trashURL)
            if trashBytes >= 10_000_000 { // >= 10 MB
                items.append(
                    QuickCleanItem(
                        id: "user-trash",
                        name: "macOS Trash Bin",
                        url: trashURL,
                        bytes: trashBytes,
                        category: .userTrash,
                        detail: "\(trashCount) items waiting in Trash",
                        isSafeByDefault: true
                    )
                )
            }
        }

        return QuickCleanScanResult(createdAt: Date(), items: items)
    }

    /// Executes safe cleanup of selected quick clean items.
    public func executeQuickClean(items: [QuickCleanItem]) async -> QuickCleanSummary {
        var totalReclaimed: Int64 = 0
        var cleanedCount = 0
        var failedCount = 0
        var categoryBreakdown: [QuickCleanCategoryKind: Int64] = [:]

        // 1. Clean browser caches
        let browserItems = items.filter { $0.category == .browserCaches }
        if !browserItems.isEmpty {
            let browserGroups = await browserCleaner.scanBrowserCaches()
            for group in browserGroups {
                let groupReclaimed = await browserCleaner.cleanCache(for: group)
                if groupReclaimed > 0 {
                    totalReclaimed += groupReclaimed
                    cleanedCount += group.fileCount
                    categoryBreakdown[.browserCaches, default: 0] += groupReclaimed
                }
            }
        }

        // 2. Clean stale logs
        let logItems = items.filter { $0.category == .systemLogs }
        for item in logItems {
            let group = SystemLogGroup(
                name: item.name,
                category: "Diagnostics",
                url: item.url,
                bytes: item.bytes,
                fileCount: 1,
                oldestFileDate: nil
            )
            let reclaimed = await logCleaner.cleanStaleLogs(in: group, olderThanDays: 14)
            if reclaimed > 0 {
                totalReclaimed += reclaimed
                cleanedCount += 1
                categoryBreakdown[.systemLogs, default: 0] += reclaimed
            }
        }

        // 3. Clean files/directories using FileTrashService
        let trashCandidates = items.filter {
            $0.category != .browserCaches && $0.category != .systemLogs && $0.category != .userTrash
        }

        if !trashCandidates.isEmpty {
            let batch = trashCandidates.map { (url: $0.url, name: $0.name, bytes: $0.bytes, category: $0.category.rawValue) }
            let summary = await MainActor.run {
                FileTrashService.shared.trashBatch(items: batch, allowAdminElevation: true)
            }
            totalReclaimed += summary.reclaimedBytes
            cleanedCount += summary.successCount
            failedCount += summary.failedItems.count

            for item in trashCandidates {
                if summary.successfulItems.contains(where: { $0.url.path == item.url.path }) {
                    categoryBreakdown[item.category, default: 0] += item.bytes
                }
            }
        }

        // 4. Handle Trash if selected
        if items.contains(where: { $0.category == .userTrash }) {
            let trashURL = home.appendingPathComponent(".Trash")
            let (trashBytes, count) = measureDirectory(trashURL)
            let success = emptyTrashContents(trashURL)
            if success {
                totalReclaimed += trashBytes
                cleanedCount += count
                categoryBreakdown[.userTrash, default: 0] += trashBytes
            }
        }

        return QuickCleanSummary(
            reclaimedBytes: totalReclaimed,
            cleanedItemsCount: cleanedCount,
            categoryBreakdown: categoryBreakdown,
            failedCount: failedCount
        )
    }

    private func measureDirectory(_ url: URL) -> (bytes: Int64, count: Int) {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return (0, 0) }

        var totalBytes: Int64 = 0
        var totalCount = 0

        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            totalBytes += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            totalCount += 1
        }
        return (totalBytes, totalCount)
    }

    private func emptyTrashContents(_ trashURL: URL) -> Bool {
        guard let contents = try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        var allOk = true
        for item in contents {
            do {
                try fm.removeItem(at: item)
            } catch {
                allOk = false
            }
        }
        return allOk
    }
}
