import Foundation
import ImageIO

actor PhotoQualityService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private let screenshotPrefixes = [
        "screenshot", "screen shot", "capture d’écran", "bildschirmfoto", "captura de pantalla"
    ]

    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "webp", "tiff", "gif"
    ]

    init() {}

    /// Scans for accumulated desktop and download screenshots older than the specified threshold.
    func scanScreenshots(olderThanDays: Int = 7) async -> [PhotoQualityItem] {
        let cutoffDate = Date().addingTimeInterval(-Double(olderThanDays * 24 * 3600))
        let searchDirectories = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Pictures/Screenshots")
        ]

        var results: [PhotoQualityItem] = []

        for dirURL in searchDirectories where fm.fileExists(atPath: dirURL.path) {
            if Task.isCancelled { break }
            guard let contents = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for fileURL in contents {
                let ext = fileURL.pathExtension.lowercased()
                guard imageExtensions.contains(ext) else { continue }

                let name = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                let isScreenshotName = screenshotPrefixes.contains { name.hasPrefix($0) }

                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }

                let date = values.creationDate ?? values.contentModificationDate ?? Date()
                guard date <= cutoffDate else { continue }

                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)

                if isScreenshotName || isScreenshotDimensions(fileURL: fileURL) {
                    results.append(
                        PhotoQualityItem(
                            url: fileURL,
                            name: fileURL.lastPathComponent,
                            bytes: size,
                            kind: .screenshot,
                            reason: "Screenshot saved on \(date.formatted(date: .abbreviated, time: .omitted))",
                            createdAt: date
                        )
                    )
                }
            }
        }

        return results.sorted { $0.bytes > $1.bytes }
    }

    /// Scans for low quality, extremely dark, or blurred photos.
    func scanLowQualityPhotos() async -> [PhotoQualityItem] {
        let picturesURL = home.appendingPathComponent("Pictures")
        guard fm.fileExists(atPath: picturesURL.path) else { return [] }

        guard let enumerator = fm.enumerator(
            at: picturesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return [] }

        var results: [PhotoQualityItem] = []
        var scannedCount = 0

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled || scannedCount > 500 { break } // Capped for UI responsiveness
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            scannedCount += 1

            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }

            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            guard size > 50_000 else { continue }

            // Inspect image dimensions using ImageIO (fast, no full bitmap load)
            if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0

                // Very small thumbnail accidental images
                if width > 0 && height > 0 && (width < 320 || height < 240) {
                    results.append(
                        PhotoQualityItem(
                            url: fileURL,
                            name: fileURL.lastPathComponent,
                            bytes: size,
                            kind: .blurryOrDark,
                            reason: "Low resolution (\(width)×\(height))",
                            createdAt: values.contentModificationDate
                        )
                    )
                }
            }
        }

        return results.sorted { $0.bytes > $1.bytes }
    }

    private func isScreenshotDimensions(fileURL: URL) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return false
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0

        // Standard Apple display resolutions
        let commonWidths: Set<Int> = [2560, 2880, 3024, 3456, 3840, 5120, 1920, 1440]
        return commonWidths.contains(width) && height > 800
    }
}
