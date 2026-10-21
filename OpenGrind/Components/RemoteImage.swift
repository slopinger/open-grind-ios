import OpenGrindKit
import SwiftUI

/// An image from Grindr's CDN, with a neutral placeholder while it loads or
/// when there is none.
struct RemoteImage: View {
    let url: URL?
    /// The longest side, in points, the image is shown at.
    var pointSize: CGFloat = 200
    var contentMode: ContentMode = .fill

    @Environment(\.imagePipeline) private var pipeline
    @Environment(\.cachesImages) private var cachesImages
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var loadedURL: URL?

    private var pixels: Int { Int((pointSize * displayScale).rounded(.up)) }

    var body: some View {
        // Already decoded images show at once, e.g. when scrolling back to them.
        let shown: UIImage? =
            if loadedURL == url {
                image
            } else if cachesImages {
                url.flatMap { pipeline?.cachedImage(at: $0, maxPixelSize: pixels) }
            } else {
                nil
            }
        ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                ImagePlaceholder()
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: loadedURL)
        .task(id: url) {
            guard let url, let pipeline else {
                image = nil
                loadedURL = nil
                return
            }
            let loaded =
                cachesImages
                ? try? await pipeline.image(at: url, maxPixelSize: pixels)
                : try? await pipeline.uncachedImage(at: url, maxPixelSize: pixels)
            if let loaded {
                image = loaded
                loadedURL = url
            }
        }
    }
}

/// The silhouette shown where a photo is missing.
struct ImagePlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                // About half the frame, whether it's an avatar or a full photo.
                GeometryReader { proxy in
                    let side = min(min(proxy.size.width, proxy.size.height) * 0.5, 120)
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A round profile photo with an optional online indicator.
struct Avatar: View {
    let photoHash: String?
    var size: CGFloat = 52
    var isOnline = false

    var body: some View {
        RemoteImage(
            url: photoHash.map { MediaURL.profileImage($0, size: .thumbnail) }, pointSize: size
        )
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(alignment: .bottomTrailing) {
            if isOnline {
                OnlineIndicator()
                    .frame(width: size * 0.26, height: size * 0.26)
                    .offset(x: -size * 0.02, y: -size * 0.02)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The green dot for profiles that are online now.
struct OnlineIndicator: View {
    var body: some View {
        Circle()
            .fill(.green)
            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            .accessibilityHidden(true)
    }
}
