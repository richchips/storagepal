import AVFoundation
import Foundation
import Quartz

actor MediaCompressorService {
    private let fm = FileManager.default

    init() {}

    func canCompress(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mov", "mp4", "m4v", "avi", "pdf"].contains(ext)
    }

    func compressFile(at sourceURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (destinationURL: URL, reclaimedBytes: Int64) {
        let ext = sourceURL.pathExtension.lowercased()
        let originalSize = Int64((try? sourceURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)

        if ext == "pdf" {
            return try compressPDF(at: sourceURL, originalSize: originalSize)
        } else {
            return try await compressVideo(at: sourceURL, originalSize: originalSize, progress: progress)
        }
    }

    private func compressPDF(at sourceURL: URL, originalSize: Int64) throws -> (destinationURL: URL, reclaimedBytes: Int64) {
        guard let pdfDoc = PDFDocument(url: sourceURL) else {
            throw NSError(domain: "MediaCompressor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open PDF file."])
        }

        let tempURL = sourceURL.deletingLastPathComponent().appendingPathComponent("\(sourceURL.deletingPathExtension().lastPathComponent)_compressed.pdf")
        pdfDoc.write(to: tempURL)

        let compressedSize = Int64((try? tempURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)
        let reclaimed = max(originalSize - compressedSize, 0)
        return (tempURL, reclaimed)
    }

    private func compressVideo(at sourceURL: URL, originalSize: Int64, progress: @escaping @Sendable (Double) -> Void) async throws -> (destinationURL: URL, reclaimedBytes: Int64) {
        let asset = AVURLAsset(url: sourceURL)
        let presetName = AVAssetExportPresetHEVC1920x1080

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw NSError(domain: "MediaCompressor", code: 2, userInfo: [NSLocalizedDescriptionKey: "HEVC video compression is not supported for this format."])
        }

        let tempURL = sourceURL.deletingLastPathComponent().appendingPathComponent("\(sourceURL.deletingPathExtension().lastPathComponent)_compressed.mp4")
        if fm.fileExists(atPath: tempURL.path) {
            try? fm.removeItem(at: tempURL)
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        if exportSession.status == .completed {
            let compressedSize = Int64((try? tempURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))?.totalFileAllocatedSize ?? 0)
            let reclaimed = max(originalSize - compressedSize, 0)
            return (tempURL, reclaimed)
        } else {
            let err = exportSession.error?.localizedDescription ?? "Video compression failed."
            throw NSError(domain: "MediaCompressor", code: 3, userInfo: [NSLocalizedDescriptionKey: err])
        }
    }
}
