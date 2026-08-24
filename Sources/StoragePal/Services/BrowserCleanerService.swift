import Foundation

actor BrowserCleanerService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    /// Scans for disposable browser HTTP caches and temporary media buffers.
    /// GUARANTEE: Never touches login sessions, saved passwords, cookies, or history.
    func scanBrowserCaches() async -> [BrowserCacheGroup] {
        var groups: [BrowserCacheGroup] = []

        let browserDefinitions: [(browser: BrowserType, paths: [String], detail: String)] = [
            (
                .safari,
                [
                    "Library/Caches/com.apple.Safari",
                    "Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari"
                ],
                "Web page media caches and temporary render data"
            ),
            (
                .chrome,
                [
                    "Library/Caches/Google/Chrome",
                    "Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage",
                    "Library/Application Support/Google/Chrome/Default/GPUCache"
                ],
                "Streaming buffers, cached images, and WebAssembly caches"
            ),
            (
                .brave,
                [
                    "Library/Caches/BraveSoftware/Brave-Browser",
                    "Library/Application Support/BraveSoftware/Brave-Browser/Default/Service Worker/CacheStorage"
                ],
                "Shielded web caches and media buffers"
            ),
            (
                .firefox,
                [
                    "Library/Caches/Firefox/Profiles",
                    "Library/Caches/Mozilla/Firefox/Profiles"
                ],
                "HTTP disk cache, startup caches, and media streams"
            ),
            (
                .edge,
                [
                    "Library/Caches/Microsoft Edge",
                    "Library/Application Support/Microsoft Edge/Default/Service Worker/CacheStorage"
                ],
                "Temporary browser caches and scripts"
            ),
            (
                .opera,
                [
                    "Library/Caches/com.operasoftware.Opera"
                ],
                "Browser web caches and graphics buffers"
            )
        ]

        for (browser, relPaths, detail) in browserDefinitions {
            if Task.isCancelled { break }
            var totalBytes: Int64 = 0
            var totalFiles = 0
            var primaryURL: URL?

            for relPath in relPaths {
                let cacheURL = home.appendingPathComponent(relPath)
                guard fm.fileExists(atPath: cacheURL.path) else { continue }
                if primaryURL == nil { primaryURL = cacheURL }

                let (bytes, count) = measureDirectory(cacheURL)
                totalBytes += bytes
                totalFiles += count
            }

            if totalBytes >= 500_000, let primaryURL { // ≥ 500 KB
                groups.append(
                    BrowserCacheGroup(
                        browser: browser,
                        cacheURL: primaryURL,
                        bytes: totalBytes,
                        fileCount: totalFiles,
                        detail: detail
                    )
                )
            }
        }

        return groups.sorted { $0.bytes > $1.bytes }
    }

    /// Cleans a browser cache group by safely removing disposable cache files.
    func cleanCache(for group: BrowserCacheGroup) async -> Int64 {
        let (reclaimed, _) = await MainActor.run { () -> (Int64, Int) in
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: group.cacheURL.path) else { return (0, 0) }

            guard let contents = try? fileManager.contentsOfDirectory(at: group.cacheURL, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
                return (0, 0)
            }

            var reclaimedBytes: Int64 = 0
            var removedCount = 0

            for fileURL in contents {
                let sz = Int64((try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)
                let result = FileTrashService.shared.trashItem(at: fileURL, allowAdminElevation: false)
                if result.isSuccess {
                    reclaimedBytes += sz
                    removedCount += 1
                }
            }

            return (reclaimedBytes, removedCount)
        }

        return reclaimed
    }

    // MARK: - Private Measurement

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
}
