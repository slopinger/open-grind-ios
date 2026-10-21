import CryptoKit
import ImageIO
import OpenGrindKit
import SwiftUI
import UIKit

/// Loads, caches and downsamples media from Grindr's CDN.
///
/// Downloads go through the transport, so they carry the same network
/// fingerprint as the official app. Files are kept on disk for a week and
/// decoded images in memory, scaled to the size they are shown at.
actor ImagePipeline {
    static let maxDownloadBytes = 25 * 1024 * 1024

    private let transport: any GrindrTransport
    /// NSCache is thread-safe, so ``cachedImage(at:maxPixelSize:)`` reads it without the actor.
    private nonisolated(unsafe) let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<(image: UIImage, download: Data?), any Error>] = [:]
    /// Counts ``removeAll()`` calls, so downloads started before one aren't written afterwards.
    private var generation = 0
    private let directory: URL

    init(transport: any GrindrTransport) {
        self.transport = transport
        memory.totalCostLimit = 96 * 1024 * 1024
        directory = URL.cachesDirectory.appending(path: "Media", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task.detached(priority: .background) { [directory] in
            Self.removeFiles(in: directory, olderThan: 7 * 86_400)
        }
    }

    /// The image at `url` if it is decoded at this size already, to show it without waiting.
    nonisolated func cachedImage(at url: URL, maxPixelSize: Int) -> UIImage? {
        memory.object(forKey: Self.memoryKey(Self.cacheKey(url), maxPixelSize))
    }

    /// The image at `url`, scaled so its longer side is at most `maxPixelSize` pixels.
    func image(at url: URL, maxPixelSize: Int) async throws -> UIImage {
        let fileName = Self.cacheKey(url)
        let key = Self.memoryKey(fileName, maxPixelSize)
        if let image = memory.object(forKey: key) { return image }
        if let task = inFlight[key as String] { return try await task.value.image }

        let file = directory.appending(path: fileName)
        let transport = transport
        let task = Task.detached(priority: .userInitiated) { () throws -> (image: UIImage, download: Data?) in
            if let cached = try? Data(contentsOf: file) {
                if let image = Self.downsample(cached, maxPixelSize: maxPixelSize) { return (image, nil) }
                try? FileManager.default.removeItem(at: file)
            }
            let download = try await Self.download(url, from: transport)
            return (try Self.decode(download, maxPixelSize: maxPixelSize), download)
        }
        inFlight[key as String] = task
        defer { if inFlight[key as String] == task { inFlight[key as String] = nil } }
        let generation = generation
        let (image, download) = try await task.value
        // Written here on the actor, so a sign-out in the meantime can't be undone by it.
        guard generation == self.generation else { return image }
        try? download?.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        memory.setObject(
            image, forKey: key, cost: Int(image.size.width * image.size.height * image.scale * 4))
        return image
    }

    /// The image at `url`, kept nowhere: not on disk and not in memory. For
    /// view-once photos.
    @concurrent
    nonisolated func uncachedImage(at url: URL, maxPixelSize: Int) async throws -> UIImage {
        try Self.decode(try await Self.download(url, from: transport), maxPixelSize: maxPixelSize)
    }

    private static func download(_ url: URL, from transport: any GrindrTransport) async throws -> Data {
        let media = try await transport.fetchMedia(at: url, maxBytes: maxDownloadBytes)
        guard media.isSuccess else { throw GrindrError.server(status: media.status, code: nil, message: nil) }
        return media.data
    }

    private static func decode(_ data: Data, maxPixelSize: Int) throws -> UIImage {
        guard let image = downsample(data, maxPixelSize: maxPixelSize) else {
            throw GrindrError.invalidResponse("not an image")
        }
        return image
    }

    /// Signed CDN URLs change their query but not their path, so the cache
    /// ignores the query.
    private static func cacheKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        let stable = components?.string ?? url.absoluteString
        return SHA256.hash(data: Data(stable.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func memoryKey(_ fileName: String, _ maxPixelSize: Int) -> NSString {
        "\(fileName)@\(maxPixelSize)" as NSString
    }

    private static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func removeFiles(in directory: URL, olderThan age: TimeInterval) {
        let manager = FileManager.default
        let files =
            (try? manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified.timeIntervalSinceNow < -age {
                try? manager.removeItem(at: file)
            }
        }
    }

    /// Deletes every cached file, e.g. on sign-out.
    func removeAll() {
        generation += 1
        for task in inFlight.values { task.cancel() }
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

extension EnvironmentValues {
    @Entry var imagePipeline: ImagePipeline? = nil
    /// False where images must not be kept anywhere, such as view-once photos.
    @Entry var cachesImages = true
}
