import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PhotoError: Error, Equatable, Sendable {
    /// Empty, corrupt, or not an image.
    case unreadable
}

/// Turns a picked photo into the two JPEGs the app stores: a full image
/// (longest edge ≤ 1600 px) and a thumbnail (≤ 320 px).
///
/// Uses ImageIO's thumbnail path, so a 48-megapixel photo is downsampled while
/// it is read and its full-size bitmap is never held in memory. Never upscales.
/// Alpha is flattened by the JPEG encoder (picked photos are photographs).
public enum PhotoProcessor {
    public static func process(_ data: Data) throws -> (full: Data, thumbnail: Data) {
        let (source, longestEdge) = try open(data)
        let full = try render(source, maxPixels: min(TakeLimits.fullPhotoMaxPixels, longestEdge))
        let thumbnail = try render(source, maxPixels: min(TakeLimits.thumbnailMaxPixels, longestEdge))
        return (full, thumbnail)
    }

    /// For a photo read from a backup, which may come from anywhere. The full image must
    /// decode; a JPEG within the size cap keeps its bytes, so a round trip doesn't
    /// recompress it, and anything else is re-rendered within the cap. The thumbnail is
    /// kept when it is a JPEG within its cap, and otherwise rebuilt from the full image.
    public static func processRestored(full: Data, thumbnail: Data) throws -> (full: Data, thumbnail: Data) {
        let (source, longestEdge) = try open(full)
        let restoredFull = isJPEG(source) && longestEdge <= TakeLimits.fullPhotoMaxPixels
            ? full
            : try render(source, maxPixels: min(TakeLimits.fullPhotoMaxPixels, longestEdge))
        if let existing = try? open(thumbnail), isJPEG(existing.source),
           existing.longestEdge <= TakeLimits.thumbnailMaxPixels {
            return (restoredFull, thumbnail)
        }
        return (restoredFull, try render(source, maxPixels: min(TakeLimits.thumbnailMaxPixels, longestEdge)))
    }

    private static func open(_ data: Data) throws -> (source: CGImageSource, longestEdge: Int) {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw PhotoError.unreadable }
        return (source, max(width, height))
    }

    private static func isJPEG(_ source: CGImageSource) -> Bool {
        (CGImageSourceGetType(source) as String?) == UTType.jpeg.identifier
    }

    private static func render(_ source: CGImageSource, maxPixels: Int) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // apply the EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoError.unreadable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoError.unreadable
        }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: TakeLimits.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.unreadable }
        return output as Data
    }
}
