import Foundation

actor ICloudEvictionService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    func findLocalICloudCandidates() async -> [FileCandidate] {
        let iCloudURL = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard fm.fileExists(atPath: iCloudURL.path) else { return [] }

        guard let enumerator = fm.enumerator(
            at: iCloudURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return [] }

        var candidates: [FileCandidate] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
                  values.isRegularFile == true,
                  values.isUbiquitousItem == true else { continue }

            // Only pick items that are currently downloaded locally on SSD
            if let status = values.ubiquitousItemDownloadingStatus, status == .current {
                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                guard size >= 10_000_000 else { continue } // >= 10 MB

                candidates.append(
                    FileCandidate(
                        id: fileURL.path,
                        url: fileURL,
                        bytes: size,
                        modifiedAt: values.contentModificationDate,
                        isCloudItem: true
                    )
                )
            }
        }
        return candidates.sorted { $0.bytes > $1.bytes }
    }

    func evictItem(at url: URL) throws -> Int64 {
        let size = Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)
        try fm.evictUbiquitousItem(at: url)
        return size
    }
}
