import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares photos for sending: at most 2048 pixels on the long side, JPEG,
/// and without metadata such as the location the photo was taken at.
enum PhotoEncoder {
    static let maxPixelSize = 2048

    struct Photo: Sendable {
        var data: Data
        var width: Int
        var height: Int
    }

    @concurrent
    static func jpeg(from data: Data) async -> Photo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        // Only the pixels are written: no EXIF, GPS or TIFF dictionaries.
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Photo(data: output as Data, width: image.width, height: image.height)
    }
}
