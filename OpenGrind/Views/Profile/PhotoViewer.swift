import OpenGrindKit
import SwiftUI

/// A photo for ``PhotoViewer``, with the ID of the view it zooms out of.
struct ViewerPhoto: Identifiable {
    let id: String
    let url: URL
}

/// Photos full screen: swipe between them, pinch or double-tap to zoom. Present
/// it as a full-screen cover with a zoom transition from the photo tapped, and
/// swiping down shrinks it back into that photo, as profiles do into the grid.
struct PhotoViewer: View {
    let photos: [ViewerPhoto]
    /// The photo on screen, so what it was opened from can follow and the zoom
    /// back lands on it.
    @Binding var selection: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $selection) {
            ForEach(photos) { photo in
                ZoomablePhoto(url: photo.url)
                    .tag(photo.id as String?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
        .background(.black)
        .ignoresSafeArea()
        .accessibilityAction(.escape) { dismiss() }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.white)
            .padding()
            .accessibilityLabel("Close")
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
    }
}

/// One photo, zoomable once the large version has loaded.
private struct ZoomablePhoto: View {
    let url: URL

    private static let pointSize: CGFloat = 1024

    @Environment(\.imagePipeline) private var pipeline
    @Environment(\.cachesImages) private var cachesImages
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomingImage(image: image)
            } else {
                // The size the profile shows, usually in memory already, so the
                // zoom transition has the photo from the start.
                RemoteImage(url: url, pointSize: 500, contentMode: .fit)
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("Photo")
        .task(id: url) {
            guard let pipeline else { return }
            let pixels = Int((Self.pointSize * displayScale).rounded(.up))
            image =
                cachesImages
                ? try? await pipeline.image(at: url, maxPixelSize: pixels)
                : try? await pipeline.uncachedImage(at: url, maxPixelSize: pixels)
        }
    }
}

/// A photo in a zooming scroll view, the standard way to zoom content: it fits
/// the screen, pinching and double-tapping zoom in, a zoomed photo pans to its
/// edges before the pager under it moves on, and it bounces like Photos.
private struct ZoomingImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingImageView {
        ZoomingImageView()
    }

    func updateUIView(_ view: ZoomingImageView, context: Context) {
        view.show(image)
    }
}

private final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ image: UIImage) {
        guard image !== imageView.image else { return }
        zoomScale = minimumZoomScale
        imageView.image = image
        imageView.frame = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Not zoomed: the photo fits the screen, e.g. again after rotating.
        if zoomScale == minimumZoomScale, let size = imageView.image?.size, size.width > 0, size.height > 0 {
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            if imageView.frame.size != fitted {
                imageView.frame = CGRect(origin: .zero, size: fitted)
                contentSize = fitted
                centerImage()
                contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
            }
        }
    }

    /// Keeps the photo in the middle while it's smaller than the screen.
    private func centerImage() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset { contentInset = inset }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    /// Zooms in on the spot tapped, or back out.
    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = tap.location(in: imageView)
            let scale = min(maximumZoomScale, 2.5)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(
                to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size),
                animated: true)
        }
    }
}
