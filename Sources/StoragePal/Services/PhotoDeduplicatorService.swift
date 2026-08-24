import Foundation
import ImageIO
import Vision

struct PhotoDuplicateGroup: Identifiable, Hashable {
    let id: String
    let bestCandidate: FileCandidate
    let duplicates: [FileCandidate]

    var wastedBytes: Int64 {
        duplicates.reduce(0) { $0 + $1.bytes }
    }

    var allCandidates: [FileCandidate] {
        [bestCandidate] + duplicates
    }
}

actor PhotoDeduplicatorService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init() {}

    func findDuplicates() async -> [PhotoDuplicateGroup] {
        let searchDirectories = [
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Downloads")
        ]
        let validExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "webp"]

        var imageURLs: [URL] = []
        for dir in searchDirectories where fm.fileExists(atPath: dir.path) {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }
                guard validExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                imageURLs.append(fileURL)
                if imageURLs.count >= 150 { break } // Bound initial scan for responsiveness
            }
        }

        struct ImagePrint {
            let candidate: FileCandidate
            let print: VNFeaturePrintObservation
        }

        var prints: [ImagePrint] = []
        for url in imageURLs {
            if Task.isCancelled { break }
            guard let featurePrint = generateFeaturePrint(for: url) else { continue }
            let size = Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let candidate = FileCandidate(
                id: url.path,
                url: url,
                bytes: size,
                modifiedAt: modDate,
                isCloudItem: false
            )
            prints.append(ImagePrint(candidate: candidate, print: featurePrint))
        }

        var processedIDs = Set<String>()
        var groups: [PhotoDuplicateGroup] = []

        for i in 0..<prints.count {
            let itemA = prints[i]
            if processedIDs.contains(itemA.candidate.id) { continue }

            var matchingDuplicates: [FileCandidate] = []
            for j in (i + 1)..<prints.count {
                let itemB = prints[j]
                if processedIDs.contains(itemB.candidate.id) { continue }

                var distance: Float = 0
                do {
                    try itemA.print.computeDistance(&distance, to: itemB.print)
                    if distance < 0.35 { // High perceptual visual similarity threshold
                        matchingDuplicates.append(itemB.candidate)
                        processedIDs.insert(itemB.candidate.id)
                    }
                } catch {
                    continue
                }
            }

            if !matchingDuplicates.isEmpty {
                processedIDs.insert(itemA.candidate.id)
                let all = ([itemA.candidate] + matchingDuplicates).sorted { $0.bytes > $1.bytes }
                let best = all[0]
                let dupes = Array(all.dropFirst())
                groups.append(
                    PhotoDuplicateGroup(
                        id: best.id,
                        bestCandidate: best,
                        duplicates: dupes
                    )
                )
            }
        }

        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    private func generateFeaturePrint(for url: URL) -> VNFeaturePrintObservation? {
        autoreleasepool {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) ?? CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }

            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        }
    }
}
