import Foundation

actor SystemLogCleanerService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    /// Scans for stale crash reports, spin dumps, and diagnostic log files older than 14 days.
    func scanStaleLogs(olderThanDays: Int = 14) async -> [SystemLogGroup] {
        let cutoffDate = Date().addingTimeInterval(-Double(olderThanDays * 24 * 3600))
        var groups: [SystemLogGroup] = []

        let logLocations: [(name: String, category: String, path: String)] = [
            ("Crash & Diagnostic Reports", "Diagnostics", "Library/Logs/DiagnosticReports"),
            ("CrashReporter Dumps", "Crash Logs", "Library/Logs/CrashReporter"),
            ("Legacy Application Logs", "App Logs", "Library/Logs")
        ]

        let logExtensions: Set<String> = ["crash", "ips", "diag", "spin", "log", "asl", "trace"]

        for (name, category, relPath) in logLocations {
            if Task.isCancelled { break }
            let dirURL = home.appendingPathComponent(relPath)
            guard fm.fileExists(atPath: dirURL.path) else { continue }

            guard let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else { continue }

            var totalBytes: Int64 = 0
            var count = 0
            var oldestDate: Date?

            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                guard logExtensions.contains(ext) || ext.isEmpty else { continue }

                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }

                if let modDate = values.contentModificationDate, modDate <= cutoffDate {
                    let sz = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    totalBytes += sz
                    count += 1
                    if oldestDate == nil || (modDate < (oldestDate ?? Date())) {
                        oldestDate = modDate
                    }
                }
            }

            if totalBytes >= 1_000_000 { // ≥ 1 MB
                groups.append(
                    SystemLogGroup(
                        name: name,
                        category: category,
                        url: dirURL,
                        bytes: totalBytes,
                        fileCount: count,
                        oldestFileDate: oldestDate
                    )
                )
            }
        }

        return groups.sorted { $0.bytes > $1.bytes }
    }

    /// Cleans stale log files within a log directory.
    func cleanStaleLogs(in group: SystemLogGroup, olderThanDays: Int = 14) async -> Int64 {
        let cutoffDate = Date().addingTimeInterval(-Double(olderThanDays * 24 * 3600))
        let logExtensions: Set<String> = ["crash", "ips", "diag", "spin", "log", "asl", "trace"]

        let reclaimed = await MainActor.run { () -> Int64 in
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: group.url,
                includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) else { return 0 }

            var bytesReclaimed: Int64 = 0

            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                guard logExtensions.contains(ext) || ext.isEmpty else { continue }

                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }

                if let modDate = values.contentModificationDate, modDate <= cutoffDate {
                    let sz = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    let result = FileTrashService.shared.trashItem(at: fileURL, allowAdminElevation: false)
                    if result.isSuccess {
                        bytesReclaimed += sz
                    }
                }
            }

            return bytesReclaimed
        }

        return reclaimed
    }
}
