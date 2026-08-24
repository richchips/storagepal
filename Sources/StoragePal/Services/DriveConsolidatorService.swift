import CryptoKit
import Foundation

actor DriveConsolidatorService {
    private let fm = FileManager.default

    init() {}

    /// Scans multiple drives / source folders and identifies cross-volume duplicate files.
    func scanCrossVolumeDuplicates(directories: [URL], minSizeBytes: Int64 = 1_000_000) async -> [CrossVolumeDuplicateGroup] {
        var sizeMap: [Int64: [VolumeFileEntry]] = [:]

        // Stage 1: Size grouping across all volumes
        for dirURL in directories {
            if Task.isCancelled { break }
            let volumeName = getVolumeName(for: dirURL)

            guard let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }

                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                guard size >= minSizeBytes else { continue }

                let entry = VolumeFileEntry(
                    volumeName: volumeName,
                    url: fileURL,
                    size: size,
                    modifiedDate: values.contentModificationDate
                )
                sizeMap[size, default: []].append(entry)
            }
        }

        // Stage 2: Streaming SHA-256 hash matching on same-size files
        var groups: [CrossVolumeDuplicateGroup] = []
        let candidateBuckets = sizeMap.filter { $0.value.count > 1 }

        for (size, entries) in candidateBuckets {
            if Task.isCancelled { break }
            var hashMap: [String: [VolumeFileEntry]] = [:]

            for entry in entries {
                if let hash = computePartialHash(for: entry.url) {
                    hashMap[hash, default: []].append(entry)
                }
            }

            for (hash, matchingEntries) in hashMap where matchingEntries.count > 1 {
                let first = matchingEntries.first!
                groups.append(
                    CrossVolumeDuplicateGroup(
                        id: hash,
                        hash: hash,
                        fileName: first.url.lastPathComponent,
                        size: size,
                        entries: matchingEntries
                    )
                )
            }
        }

        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    /// Creates a consolidation plan to merge multiple folders into one destination without duplicates.
    func buildConsolidationPlan(sourceDirectories: [URL], targetDirectory: URL) async -> DriveConsolidationPlan {
        let duplicates = await scanCrossVolumeDuplicates(directories: sourceDirectories)
        let redundantBytes = duplicates.reduce(0) { $0 + $1.wastedBytes }

        var totalFiles = 0
        var totalBytes: Int64 = 0

        for dir in sourceDirectories {
            let (count, bytes) = measureDirectory(dir)
            totalFiles += count
            totalBytes += bytes
        }

        let volumeNames = sourceDirectories.map { getVolumeName(for: $0) }

        return DriveConsolidationPlan(
            sourceVolumes: volumeNames,
            targetDirectory: targetDirectory,
            totalFilesToConsolidate: totalFiles,
            totalBytesToCopy: max(0, totalBytes - redundantBytes),
            redundantDuplicateBytesSaved: redundantBytes
        )
    }

    // MARK: - Private Helpers

    private func getVolumeName(for url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.volumeNameKey]),
           let name = values.volumeName, !name.isEmpty {
            return name
        }
        return url.lastPathComponent
    }

    private func computePartialHash(for fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let sampleSize = 128 * 1024 // 128 KB header chunk
        let headerData = handle.readData(ofLength: sampleSize)
        hasher.update(data: headerData)

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func measureDirectory(_ url: URL) -> (count: Int, bytes: Int64) {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return (0, 0) }

        var count = 0
        var bytes: Int64 = 0

        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }

        return (count, bytes)
    }
}
