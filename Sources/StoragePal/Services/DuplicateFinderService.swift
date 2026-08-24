import CryptoKit
import Foundation

struct DuplicateFileGroup: Identifiable, Hashable {
    let id: String
    let fileSize: Int64
    let hash: String
    let originalCandidate: FileCandidate
    let duplicates: [FileCandidate]

    var wastedBytes: Int64 {
        fileSize * Int64(duplicates.count)
    }

    var allCandidates: [FileCandidate] {
        [originalCandidate] + duplicates
    }
}

actor DuplicateFinderService {
    private let fm = FileManager.default

    init() {}

    func scanDuplicates(in targetURL: URL, minSizeBytes: Int64 = 1_000_000) async -> [DuplicateFileGroup] {
        guard let enumerator = fm.enumerator(
            at: targetURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                Task { @MainActor in
                    AppErrorLogService.shared.log(category: "DuplicateFinder", message: "Failed to access \(url.path)", details: error.localizedDescription)
                }
                return true
            }
        ) else { return [] }

        // Step 1: Collect files and group by exact byte size
        var sizeBuckets: [Int64: [URL]] = [:]
        var modDates: [URL: Date] = [:]

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }

            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            guard size >= minSizeBytes else { continue }

            sizeBuckets[size, default: []].append(fileURL)
            if let date = values.contentModificationDate {
                modDates[fileURL] = date
            }
        }

        // Filter out buckets with only 1 file
        let candidateBuckets = sizeBuckets.filter { $0.value.count > 1 }

        var groups: [DuplicateFileGroup] = []

        // Step 2 & 3: Fast partial hash + Full SHA256 verification
        for (size, urls) in candidateBuckets {
            if Task.isCancelled { break }

            var hashGroups: [String: [URL]] = [:]
            for url in urls {
                if let hash = computeSHA256(for: url) {
                    hashGroups[hash, default: []].append(url)
                }
            }

            for (hash, matchingURLs) in hashGroups where matchingURLs.count > 1 {
                // Sort by modification date: oldest is treated as original, newer are duplicates
                let sortedURLs = matchingURLs.sorted { (modDates[$0] ?? .distantPast) < (modDates[$1] ?? .distantPast) }

                let originalURL = sortedURLs[0]
                let dupeURLs = Array(sortedURLs.dropFirst())

                let originalCandidate = FileCandidate(
                    id: originalURL.path,
                    url: originalURL,
                    bytes: size,
                    modifiedAt: modDates[originalURL],
                    isCloudItem: false
                )

                let duplicateCandidates = dupeURLs.map { url in
                    FileCandidate(
                        id: url.path,
                        url: url,
                        bytes: size,
                        modifiedAt: modDates[url],
                        isCloudItem: false
                    )
                }

                groups.append(
                    DuplicateFileGroup(
                        id: "\(hash)_\(size)",
                        fileSize: size,
                        hash: hash,
                        originalCandidate: originalCandidate,
                        duplicates: duplicateCandidates
                    )
                )
            }
        }

        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    private func computeSHA256(for url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024 // 64 KB stream chunks

        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: bufferSize)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
