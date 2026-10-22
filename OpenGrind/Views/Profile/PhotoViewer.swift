import OpenGrindKit
import SwiftUI

/// Photos to show full screen.
struct ShownPhotos: Identifiable {
    let urls: [URL]
    let selection: Int
    /// Off for view-once photos, which mustn't be kept.
    let cachesImages: Bool
    let id = UUID()
}

/// Opens photos full screen, over whatever has ``View/photoViewerHost()``,
/// bars included.
@MainActor @Observable
final class PhotoViewerPresenter {
    fileprivate(set) var shown: ShownPhotos?

    func show(_ urls: [URL], at selection: Int = 0, cachesImages: Bool = true) {
        // The keyboard is above every view and would stay up over the photo.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeOut(duration: 0.2)) {
            shown = ShownPhotos(urls: urls, selection: selection, cachesImages: cachesImages)
        }
    }

    fileprivate func close() {
        withAnimation(.easeOut(duration: 0.2)) { shown = nil }
    }
}

extension View {
    /// Shows photos opened with ``PhotoViewerPresenter`` over this view. An
    /// overlay rather than a full-screen cover, so what they were opened from
    /// shows through while pulling them away: a clear presentation background
    /// also took the background off the profile's own full-screen cover.
    func photoViewerHost() -> some View {
        modifier(PhotoViewerHost())
    }
}

private struct PhotoViewerHost: ViewModifier {
    @State private var presenter = PhotoViewerPresenter()

    func body(content: Content) -> some View {
        content
            .environment(presenter)
            .accessibilityHidden(presenter.shown != nil)
            .overlay {
                if let shown = presenter.shown {
                    PhotoViewer(urls: shown.urls, selection: shown.selection) { presenter.close() }
                        .environment(\.cachesImages, shown.cachesImages)
                        .id(shown.id)
                        .transition(.opacity)
                }
            }
    }
}

/// Photos full screen: swipe between them, pinch or double-tap to zoom, swipe
/// up or down to close.
private struct PhotoViewer: View {
    let urls: [URL]
    @State var selection: Int
    let close: () -> Void
    /// How far the photo is pulled towards closing, from 0 to 1: it shrinks and
    /// the controls fade.
    @State private var pull: Double = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(urls.indices, id: \.self) { index in
                ZoomablePhoto(url: urls[index], pull: $pull, close: close)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 && pull == 0 ? .always : .never))
        // Gone within a short pull, to show what the photo was opened from.
        .background(.black.opacity(max(1 - pull * 5, 0)))
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.white)
            .padding()
            .opacity(1 - pull)
            .accessibilityLabel("Close")
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
    }
}

private struct ZoomablePhoto: View {
    let url: URL
    @Binding var pull: Double
    let close: () -> Void

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        RemoteImage(url: url, pointSize: 1024, contentMode: .fit)
            .scaleEffect(scale * CGFloat(1 - pull * 0.3))
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(max(committedScale * value.magnification, 1), 4) }
                    .onEnded { _ in
                        committedScale = scale
                        if scale == 1 { reset() }
                    }
            )
            .simultaneousGesture(scale > 1 ? pan : nil)
            .gesture(VerticalPan(isEnabled: scale == 1, changed: pullChanged, ended: pullEnded))
            .onTapGesture(count: 2) {
                withAnimation(.spring) {
                    if scale > 1 {
                        reset()
                    } else {
                        scale = 2.5
                        committedScale = 2.5
                    }
                }
            }
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Photo")
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height)
            }
            .onEnded { _ in committedOffset = offset }
    }

    /// Pulling up or down to close: the photo follows the finger.
    private func pullChanged(_ moved: CGSize) {
        offset = moved
        pull = min(Double(abs(moved.height)) / 400, 1)
    }

    /// Far or fast enough closes, otherwise the photo springs back.
    private func pullEnded(_ moved: CGSize, velocity: CGSize) {
        if abs(moved.height) > 120 || abs(velocity.height) > 800 {
            close()
        } else {
            withAnimation(.spring) {
                offset = .zero
                pull = 0
            }
        }
    }

    private func reset() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
    }
}

/// A one-finger pan that only starts when it moves more up or down than
/// sideways, so the pager under it still gets sideways swipes and a pinch still
/// zooms. A SwiftUI drag gesture can't decline a touch that way: it took every
/// swipe from the pager.
private struct VerticalPan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    let changed: (CGSize) -> Void
    let ended: (CGSize, _ velocity: CGSize) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        let moved = CGSize(width: translation.x, height: translation.y)
        switch recognizer.state {
        case .changed:
            changed(moved)
        case .ended, .cancelled, .failed:
            let velocity = recognizer.velocity(in: recognizer.view)
            ended(moved, CGSize(width: velocity.x, height: velocity.y))
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, pan.numberOfTouches == 1 else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }

        /// Everything else waits for this pan to decline: the pager, so a vertical
        /// swipe doesn't move it too, and the profile cover's own swipe down, which
        /// would zoom the whole profile back into the grid.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
