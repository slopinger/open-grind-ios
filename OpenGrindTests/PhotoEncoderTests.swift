import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import OpenGrind

struct PhotoEncoderTests {
    @Test func photosLoseTheirLocationAndAreScaledDown() async throws {
        let original = try Self.jpeg(width: 4000, height: 3000, latitude: 52.52, longitude: 13.405)
        #expect(Self.properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let encoded = try #require(await PhotoEncoder.jpeg(from: original))
        #expect(encoded.width == PhotoEncoder.maxPixelSize && encoded.height == 1536)
        let properties = Self.properties(of: encoded.data)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == PhotoEncoder.maxPixelSize)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1536)
    }

    @Test func unreadableDataIsRejected() async {
        #expect(await PhotoEncoder.jpeg(from: Data("not a photo".utf8)) == nil)
    }

    private static func jpeg(width: Int, height: Int, latitude: Double, longitude: Double) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: latitude, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: longitude, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func properties(of data: Data) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [:] }
        return properties
    }
}
