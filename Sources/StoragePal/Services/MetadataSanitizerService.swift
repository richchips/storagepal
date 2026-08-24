import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

actor MetadataSanitizerService {
    private let fm = FileManager.default

    init() {}

    /// Inspects a file to detect sensitive metadata (GPS coordinates, camera model, author, etc.)
    func inspectMetadata(for fileURL: URL) -> SanitizerMetadataReport {
        let ext = fileURL.pathExtension.lowercased()

        if isImage(extension: ext) {
            return inspectImageMetadata(for: fileURL)
        } else if ext == "pdf" {
            return inspectPDFMetadata(for: fileURL)
        }

        return SanitizerMetadataReport(
            hasGPS: false,
            gpsCoordinates: nil,
            cameraModel: nil,
            author: nil,
            software: nil,
            creationDate: nil,
            tagsCount: 0
        )
    }

    /// Strips sensitive metadata from an image or PDF and exports a clean sanitized copy.
    func sanitizeFile(at sourceURL: URL, destinationDirectory: URL) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        let cleanFileName = "\(sourceURL.deletingPathExtension().lastPathComponent)_sanitized.\(ext)"
        let targetURL = destinationDirectory.appendingPathComponent(cleanFileName)

        if isImage(extension: ext) {
            try sanitizeImage(sourceURL: sourceURL, targetURL: targetURL)
        } else if ext == "pdf" {
            try sanitizePDF(sourceURL: sourceURL, targetURL: targetURL)
        } else {
            try fm.copyItem(at: sourceURL, to: targetURL)
        }

        return targetURL
    }

    // MARK: - Private Image Processing

    private func isImage(extension ext: String) -> Bool {
        ["jpg", "jpeg", "png", "heic", "tiff", "webp"].contains(ext)
    }

    private func inspectImageMetadata(for fileURL: URL) -> SanitizerMetadataReport {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return SanitizerMetadataReport(hasGPS: false, gpsCoordinates: nil, cameraModel: nil, author: nil, software: nil, creationDate: nil, tagsCount: 0)
        }

        var hasGPS = false
        var coords: String?
        var camera: String?
        var software: String?
        var author: String?
        var count = 0

        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            hasGPS = true
            count += gps.count
            if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                coords = String(format: "%.4f° %@, %.4f° %@", lat, latRef, lon, lonRef)
            }
        }

        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            count += tiff.count
            let make = tiff[kCGImagePropertyTIFFMake] as? String ?? ""
            let model = tiff[kCGImagePropertyTIFFModel] as? String ?? ""
            if !make.isEmpty || !model.isEmpty {
                camera = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            }
            software = tiff[kCGImagePropertyTIFFSoftware] as? String
            author = tiff[kCGImagePropertyTIFFArtist] as? String
        }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            count += exif.count
            if camera == nil, let lensModel = exif[kCGImagePropertyExifLensModel] as? String {
                camera = lensModel
            }
        }

        let date = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        return SanitizerMetadataReport(
            hasGPS: hasGPS,
            gpsCoordinates: coords,
            cameraModel: camera,
            author: author,
            software: software,
            creationDate: date,
            tagsCount: count
        )
    }

    private func sanitizeImage(sourceURL: URL, targetURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let imageType = CGImageSourceGetType(source),
              let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, imageType, 1, nil) else {
            throw NSError(domain: "Sanitizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read image for sanitization."])
        }

        // Empty metadata dictionary ensures no EXIF/GPS tags are copied over
        let cleanProperties: [CFString: Any] = [:]
        CGImageDestinationAddImageFromSource(destination, source, 0, cleanProperties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "Sanitizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write sanitized image."])
        }
    }

    // MARK: - Private PDF Processing

    private func inspectPDFMetadata(for fileURL: URL) -> SanitizerMetadataReport {
        guard let pdf = PDFDocument(url: fileURL) else {
            return SanitizerMetadataReport(hasGPS: false, gpsCoordinates: nil, cameraModel: nil, author: nil, software: nil, creationDate: nil, tagsCount: 0)
        }

        let attrs = pdf.documentAttributes ?? [:]
        let author = attrs[PDFDocumentAttribute.authorAttribute] as? String
        let producer = attrs[PDFDocumentAttribute.producerAttribute] as? String ?? attrs[PDFDocumentAttribute.creatorAttribute] as? String
        let date = attrs[PDFDocumentAttribute.creationDateAttribute] as? Date

        return SanitizerMetadataReport(
            hasGPS: false,
            gpsCoordinates: nil,
            cameraModel: nil,
            author: author,
            software: producer,
            creationDate: date,
            tagsCount: attrs.count
        )
    }

    private func sanitizePDF(sourceURL: URL, targetURL: URL) throws {
        guard let pdf = PDFDocument(url: sourceURL) else {
            throw NSError(domain: "Sanitizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to read PDF document."])
        }

        pdf.documentAttributes = [:]
        guard pdf.write(to: targetURL) else {
            throw NSError(domain: "Sanitizer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to write sanitized PDF."])
        }
    }
}
