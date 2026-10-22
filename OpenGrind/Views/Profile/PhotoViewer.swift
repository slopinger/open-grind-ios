import OpenGrindKit
import SwiftUI

/// Photos full screen: swipe between them, pinch or double-tap to zoom, swipe
/// up or down to close.
struct PhotoViewer: View {
    let urls: [URL]
    @State var selection: Int
    /// How far the photo is pulled towards closing, from 0 to 1: it shrinks and
    /// the controls fade.
    @State private var pull: Double = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $selection) {
            ForEach(urls.indices, id: \.self) { index in
                ZoomablePhoto(url: urls[index], pull: $pull) { dismiss() }
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 && pull == 0 ? .always : .never))
        // Solid: a clear presentation background, to see the profile while pulling,
        // took the background off the profile's own full-screen cover as well.
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

/// A pan that only starts when it moves more up or down than sideways, so the
/// pager under it still gets sideways swipes. A SwiftUI drag gesture can't
/// decline a touch that way: it took every swipe from the pager.
private struct VerticalPan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    let changed: (CGSize) -> Void
    let ended: (CGSize, _ velocity: CGSize) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
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
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }

        /// The pager waits for this pan to decline before it scrolls, so a vertical
        /// swipe doesn't move it too.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            other.view is UIScrollView
        }
    }
}
