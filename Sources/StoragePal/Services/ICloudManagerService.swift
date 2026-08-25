import Foundation
import AppKit

actor ICloudManagerService {
    static let shared = ICloudManagerService()

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    // MARK: - Deep Scan & Folder Aggregation

    func scanICloudStorage() async -> ICloudUntangleReport {
        let mobileDocsURL = home.appendingPathComponent("Library/Mobile Documents")
        let cloudDocsURL = mobileDocsURL.appendingPathComponent("com~apple~CloudDocs")

        guard fm.fileExists(atPath: mobileDocsURL.path) else {
            return .empty
        }

        // 1. Gather installed application bundle IDs to identify ghost app containers
        let installedBundleIDs = getInstalledApplicationBundleIDs()

        var totalLogicalBytes: Int64 = 0
        var totalLocalSSDBytes: Int64 = 0
        var totalEvictedBytes: Int64 = 0
        var topFolders: [ICloudFolderNode] = []
        var appContainers: [ICloudFolderNode] = []
        var clutterCandidates: [ICloudClutterItem] = []
        var allDownloadedFiles: [ICloudFileItem] = []
        var conflictsCount: Int = 0

        // 2. Scan primary iCloud Drive folders (inside com~apple~CloudDocs)
        if fm.fileExists(atPath: cloudDocsURL.path) {
            let primaryReport = scanICloudDriveRoot(
                cloudDocsURL: cloudDocsURL,
                installedBundleIDs: installedBundleIDs
            )
            topFolders.append(contentsOf: primaryReport.folders)
            clutterCandidates.append(contentsOf: primaryReport.clutter)
            allDownloadedFiles.append(contentsOf: primaryReport.downloadedFiles)
            conflictsCount += primaryReport.conflictsCount
            totalLogicalBytes += primaryReport.totalLogical
            totalLocalSSDBytes += primaryReport.totalPhysical
        }

        // 3. Scan ubiquity app containers (sibling directories inside ~/Library/Mobile Documents)
        let containerReport = scanAppUbiquityContainers(
            mobileDocsURL: mobileDocsURL,
            installedBundleIDs: installedBundleIDs
        )
        appContainers.append(contentsOf: containerReport.containers)
        clutterCandidates.append(contentsOf: containerReport.clutter)
        allDownloadedFiles.append(contentsOf: containerReport.downloadedFiles)
        conflictsCount += containerReport.conflictsCount
        totalLogicalBytes += containerReport.totalLogical
        totalLocalSSDBytes += containerReport.totalPhysical

        totalEvictedBytes = max(0, totalLogicalBytes - totalLocalSSDBytes)

        // Sort folders and files by size descending
        topFolders.sort { $0.totalLogicalBytes > $1.totalLogicalBytes }
        appContainers.sort { $0.totalLogicalBytes > $1.totalLogicalBytes }
        clutterCandidates.sort { $0.bytes > $1.bytes }
        allDownloadedFiles.sort { $0.bytes > $1.bytes }

        return ICloudUntangleReport(
            totalICloudBytes: totalLogicalBytes,
            totalLocalSSDBytes: totalLocalSSDBytes,
            totalEvictedCloudBytes: totalEvictedBytes,
            topFolders: topFolders,
            appContainers: appContainers,
            clutterCandidates: clutterCandidates,
            downloadedFiles: allDownloadedFiles,
            conflictsCount: conflictsCount,
            scannedAt: Date()
        )
    }

    // MARK: - Subdirectory Scanning Engine

    private struct SubscanResult {
        var folders: [ICloudFolderNode] = []
        var containers: [ICloudFolderNode] = []
        var clutter: [ICloudClutterItem] = []
        var downloadedFiles: [ICloudFileItem] = []
        var conflictsCount: Int = 0
        var totalLogical: Int64 = 0
        var totalPhysical: Int64 = 0
    }

    private func scanICloudDriveRoot(cloudDocsURL: URL, installedBundleIDs: Set<String>) -> SubscanResult {
        var result = SubscanResult()

        guard let contents = try? fm.contentsOfDirectory(
            at: cloudDocsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        for itemURL in contents {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir {
                let folderNode = analyzeFolder(url: itemURL, isAppContainer: false, appIdentifier: nil)
                result.folders.append(folderNode)
                result.totalLogical += folderNode.totalLogicalBytes
                result.totalPhysical += folderNode.localPhysicalBytes

                // Collect clutter & downloaded files from folder
                let (folderClutter, folderDownloaded, folderConflicts) = inspectFolderFiles(folderURL: itemURL)
                result.clutter.append(contentsOf: folderClutter)
                result.downloadedFiles.append(contentsOf: folderDownloaded)
                result.conflictsCount += folderConflicts
            } else {
                // Top-level loose file
                let fileItem = analyzeSingleFile(url: itemURL)
                result.totalLogical += fileItem.bytes
                if fileItem.isDownloadedLocally {
                    result.totalPhysical += fileItem.bytes
                    result.downloadedFiles.append(fileItem)
                }
                if let clutterItem = evaluateClutter(for: fileItem) {
                    result.clutter.append(clutterItem)
                }
                if fileItem.hasSyncConflict {
                    result.conflictsCount += 1
                }
            }
        }

        return result
    }

    private func scanAppUbiquityContainers(mobileDocsURL: URL, installedBundleIDs: Set<String>) -> SubscanResult {
        var result = SubscanResult()

        guard let containers = try? fm.contentsOfDirectory(
            at: mobileDocsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        for containerURL in containers {
            let name = containerURL.lastPathComponent
            // Skip the main CloudDocs folder as it's scanned separately
            if name == "com~apple~CloudDocs" { continue }

            let appID = extractBundleID(from: name)
            let isGhost = appID != nil && !installedBundleIDs.contains(appID!)

            let folderNode = analyzeFolder(
                url: containerURL,
                isAppContainer: true,
                appIdentifier: appID
            )

            result.containers.append(folderNode)
            result.totalLogical += folderNode.totalLogicalBytes
            result.totalPhysical += folderNode.localPhysicalBytes

            let (folderClutter, folderDownloaded, folderConflicts) = inspectFolderFiles(folderURL: containerURL)
            result.clutter.append(contentsOf: folderClutter)
            result.downloadedFiles.append(contentsOf: folderDownloaded)
            result.conflictsCount += folderConflicts

            // Flag abandoned ghost app container if not installed
            if isGhost && folderNode.totalLogicalBytes > 0 {
                result.clutter.append(
                    ICloudClutterItem(
                        url: containerURL,
                        name: folderNode.name,
                        bytes: folderNode.totalLogicalBytes,
                        kind: .abandonedAppContainer,
                        reason: "App '\(appID ?? name)' is not installed on this Mac",
                        isDownloadedLocally: folderNode.localPhysicalBytes > 0
                    )
                )
            }
        }

        return result
    }

    // MARK: - Folder & File Analyzer Helpers

    private func analyzeFolder(url: URL, isAppContainer: Bool, appIdentifier: String?) -> ICloudFolderNode {
        var totalLogical: Int64 = 0
        var totalPhysical: Int64 = 0
        var fileCount = 0
        var downloadedCount = 0
        var largestFiles: [ICloudFileItem] = []

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemHasUnresolvedConflictsKey
            ],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return ICloudFolderNode(
                url: url,
                name: friendlyFolderName(for: url),
                icon: iconForFolder(url: url, isAppContainer: isAppContainer),
                totalLogicalBytes: 0,
                localPhysicalBytes: 0,
                cloudOnlyBytes: 0,
                fileCount: 0,
                downloadedFileCount: 0,
                isAppContainer: isAppContainer,
                appIdentifier: appIdentifier,
                subfolders: [],
                largestFiles: []
            )
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard let vals = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemHasUnresolvedConflictsKey
            ]), vals.isRegularFile == true else { continue }

            fileCount += 1
            let logicalSize = Int64(vals.fileSize ?? vals.totalFileAllocatedSize ?? 0)
            totalLogical += logicalSize

            let isDownloaded = vals.ubiquitousItemDownloadingStatus == .current
            if isDownloaded {
                downloadedCount += 1
                let physicalSize = Int64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
                totalPhysical += physicalSize
            }

            let hasConflict = (vals.ubiquitousItemHasUnresolvedConflicts ?? false) ||
                fileURL.lastPathComponent.contains("(conflicted copy") ||
                fileURL.lastPathComponent.contains(" 2.")

            if logicalSize >= 5_000_000 { // Track files >= 5 MB
                let item = ICloudFileItem(
                    url: fileURL,
                    name: fileURL.lastPathComponent,
                    bytes: logicalSize,
                    isDownloadedLocally: isDownloaded,
                    hasSyncConflict: hasConflict,
                    modifiedAt: vals.contentModificationDate,
                    category: fileCategory(for: fileURL)
                )
                largestFiles.append(item)
            }
        }

        largestFiles.sort { $0.bytes > $1.bytes }
        let cloudOnly = max(0, totalLogical - totalPhysical)

        return ICloudFolderNode(
            url: url,
            name: friendlyFolderName(for: url),
            icon: iconForFolder(url: url, isAppContainer: isAppContainer),
            totalLogicalBytes: totalLogical,
            localPhysicalBytes: totalPhysical,
            cloudOnlyBytes: cloudOnly,
            fileCount: fileCount,
            downloadedFileCount: downloadedCount,
            isAppContainer: isAppContainer,
            appIdentifier: appIdentifier,
            subfolders: [],
            largestFiles: Array(largestFiles.prefix(8))
        )
    }

    private func inspectFolderFiles(folderURL: URL) -> (clutter: [ICloudClutterItem], downloaded: [ICloudFileItem], conflicts: Int) {
        var clutter: [ICloudClutterItem] = []
        var downloaded: [ICloudFileItem] = []
        var conflicts = 0

        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemHasUnresolvedConflictsKey
            ],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return (clutter, downloaded, conflicts)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard let vals = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemHasUnresolvedConflictsKey
            ]), vals.isRegularFile == true else { continue }

            let logicalSize = Int64(vals.fileSize ?? vals.totalFileAllocatedSize ?? 0)
            let isDownloaded = vals.ubiquitousItemDownloadingStatus == .current
            let hasConflict = (vals.ubiquitousItemHasUnresolvedConflicts ?? false) ||
                fileURL.lastPathComponent.contains("(conflicted copy") ||
                fileURL.lastPathComponent.contains(" 2.")

            if hasConflict {
                conflicts += 1
            }

            let fileItem = ICloudFileItem(
                url: fileURL,
                name: fileURL.lastPathComponent,
                bytes: logicalSize,
                isDownloadedLocally: isDownloaded,
                hasSyncConflict: hasConflict,
                modifiedAt: vals.contentModificationDate,
                category: fileCategory(for: fileURL)
            )

            if isDownloaded && logicalSize >= 10_000_000 { // Downloaded files >= 10 MB
                downloaded.append(fileItem)
            }

            if let clutterItem = evaluateClutter(for: fileItem) {
                clutter.append(clutterItem)
            }
        }

        return (clutter, downloaded, conflicts)
    }

    private func analyzeSingleFile(url: URL) -> ICloudFileItem {
        guard let vals = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemHasUnresolvedConflictsKey
        ]) else {
            return ICloudFileItem(
                url: url,
                name: url.lastPathComponent,
                bytes: 0,
                isDownloadedLocally: false,
                hasSyncConflict: false,
                modifiedAt: nil,
                category: "Other"
            )
        }

        let logicalSize = Int64(vals.fileSize ?? vals.totalFileAllocatedSize ?? 0)
        let isDownloaded = vals.ubiquitousItemDownloadingStatus == .current
        let hasConflict = (vals.ubiquitousItemHasUnresolvedConflicts ?? false) ||
            url.lastPathComponent.contains("(conflicted copy") ||
            url.lastPathComponent.contains(" 2.")

        return ICloudFileItem(
            url: url,
            name: url.lastPathComponent,
            bytes: logicalSize,
            isDownloadedLocally: isDownloaded,
            hasSyncConflict: hasConflict,
            modifiedAt: vals.contentModificationDate,
            category: fileCategory(for: url)
        )
    }

    private func evaluateClutter(for item: ICloudFileItem) -> ICloudClutterItem? {
        let ext = item.url.pathExtension.lowercased()

        // 1. Sync conflict duplicate
        if item.hasSyncConflict {
            return ICloudClutterItem(
                url: item.url,
                name: item.name,
                bytes: item.bytes,
                kind: .syncConflict,
                reason: "Conflicted sync replica or duplicate cloud revision",
                isDownloadedLocally: item.isDownloadedLocally
            )
        }

        // 2. Large Installer / Disk Image
        if ["dmg", "pkg", "iso"].contains(ext) && item.bytes >= 20_000_000 {
            return ICloudClutterItem(
                url: item.url,
                name: item.name,
                bytes: item.bytes,
                kind: .oldInstaller,
                reason: "Disk image or application installer taking cloud space",
                isDownloadedLocally: item.isDownloadedLocally
            )
        }

        // 3. Large Archive / Backup
        if ["zip", "tar", "gz", "tgz", "rar", "7z", "bz2"].contains(ext) && item.bytes >= 50_000_000 {
            return ICloudClutterItem(
                url: item.url,
                name: item.name,
                bytes: item.bytes,
                kind: .largeArchive,
                reason: "Compressed archive or legacy backup file",
                isDownloadedLocally: item.isDownloadedLocally
            )
        }

        // 4. Oversized Video / Raw Media
        if ["mov", "mp4", "m4v", "mkv", "avi", "raw", "cr2", "nef", "arw"].contains(ext) && item.bytes >= 200_000_000 {
            return ICloudClutterItem(
                url: item.url,
                name: item.name,
                bytes: item.bytes,
                kind: .oversizedMedia,
                reason: "Large media file (\(ByteText.string(item.bytes)))",
                isDownloadedLocally: item.isDownloadedLocally
            )
        }

        return nil
    }

    // MARK: - Remediation Actions (Evict, Download, Trash)

    func evictFile(at url: URL) throws -> Int64 {
        let size = Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)
        try fm.evictUbiquitousItem(at: url)
        return size
    }

    func evictFolder(at folderURL: URL) async throws -> (filesEvicted: Int, bytesReclaimed: Int64) {
        var count = 0
        var totalBytes: Int64 = 0

        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return (0, 0)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .ubiquitousItemDownloadingStatusKey]),
                  vals.isRegularFile == true,
                  vals.ubiquitousItemDownloadingStatus == .current else { continue }

            let size = Int64(vals.totalFileAllocatedSize ?? 0)
            do {
                try fm.evictUbiquitousItem(at: fileURL)
                count += 1
                totalBytes += size
            } catch {
                // Continue with remaining files
            }
        }

        return (count, totalBytes)
    }

    func downloadItem(at url: URL) throws {
        try fm.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - Bundle ID & Friendly Naming

    private func getInstalledApplicationBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appendingPathComponent("Applications")
        ]

        for path in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for appURL in contents where appURL.pathExtension.lowercased() == "app" {
                if let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier {
                    ids.insert(bundleID)
                }
            }
        }
        return ids
    }

    private func extractBundleID(from containerName: String) -> String? {
        // e.g. "iCloud~com~apple~Keynote" -> "com.apple.Keynote"
        // e.g. "iCloud~md~obsidian" -> "md.obsidian"
        if containerName.hasPrefix("iCloud~") {
            let raw = containerName.dropFirst("iCloud~".count)
            return raw.replacingOccurrences(of: "~", with: ".")
        } else if containerName.contains("~") {
            return containerName.replacingOccurrences(of: "~", with: ".")
        }
        return nil
    }

    private func friendlyFolderName(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasPrefix("iCloud~") {
            let bundleID = extractBundleID(from: name) ?? name
            let parts = bundleID.split(separator: ".")
            return parts.last.map { String($0).capitalized } ?? name
        }
        return name
    }

    private func iconForFolder(url: URL, isAppContainer: Bool) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.contains("desktop") { return "menubar.dock.rectangle" }
        if name.contains("document") { return "folder.fill" }
        if name.contains("download") { return "arrow.down.circle.fill" }
        if name.contains("keynote") { return "presentation.fill" }
        if name.contains("pages") { return "doc.richtext.fill" }
        if name.contains("numbers") { return "tablecells.fill" }
        if name.contains("obsidian") { return "note.text" }
        if name.contains("goodnote") { return "pencil.and.outline" }
        if isAppContainer { return "app.fill" }
        return "folder.fill"
    }

    private func fileCategory(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v", "mkv", "avi"].contains(ext) { return "Video" }
        if ["png", "jpg", "jpeg", "heic", "gif", "svg", "raw", "cr2", "nef"].contains(ext) { return "Picture" }
        if ["zip", "dmg", "pkg", "tar", "gz", "rar", "7z", "iso"].contains(ext) { return "Archive" }
        if ["pdf", "doc", "docx", "pages", "key", "numbers", "txt", "md", "csv", "xlsx"].contains(ext) { return "Document" }
        if ["mp3", "wav", "m4a", "flac", "aac"].contains(ext) { return "Audio" }
        return "Other"
    }
}
