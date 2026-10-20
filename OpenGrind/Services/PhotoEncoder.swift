import Foundation
import ImageIO
import OpenGrindKit
import PhotosUI
import UniformTypeIdentifiers

/// Prepares photos for sending: at most 2048 pixels on the long side, JPEG,
/// and without metadata such as the location the photo was taken at.
enum PhotoEncoder {
    static let maxPixelSize = 2048

    /// The picked photo as a JPEG; `nil` when it isn't an image that can be read.
    @concurrent
    static func jpeg(from item: PhotosPickerItem) async throws -> JPEGPhoto? {
        guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
        return await jpeg(from: data)
    }

    @concurrent
    static func jpeg(from data: Data) async -> JPEGPhoto? {
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
        return JPEGPhoto(data: output as Data, width: image.width, height: image.height)
    }
}
