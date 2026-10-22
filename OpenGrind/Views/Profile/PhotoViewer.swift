import OpenGrindKit
import SwiftUI

/// Photos full screen: swipe between them, pinch or double-tap to zoom, swipe
/// up or down to close.
struct PhotoViewer: View {
    let urls: [URL]
    @State var selection: Int
    /// How far the photo is pulled towards closing, from 0 to 1.
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
        // What it was opened from shows through while pulling.
        .background(.black.opacity(1 - pull))
        .presentationBackground(.clear)
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
    /// Whether the drag going on closes the viewer; decided by its first move,
    /// so sideways drags still go to the next photo.
    @State private var isPulling: Bool?

    var body: some View {
        RemoteImage(url: url, pointSize: 1024, contentMode: .fit)
            .scaleEffect(scale * (1 - pull * 0.3))
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
            .simultaneousGesture(scale > 1 ? nil : pullToClose)
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

    /// Follows the finger up or down; far or fast enough closes, otherwise the
    /// photo springs back.
    private var pullToClose: some Gesture {
        DragGesture()
            .onChanged { value in
                let moved = value.translation
                if isPulling == nil { isPulling = abs(moved.height) > abs(moved.width) }
                guard isPulling == true else { return }
                offset = moved
                pull = min(abs(moved.height) / 400, 1)
            }
            .onEnded { value in
                defer { isPulling = nil }
                guard isPulling == true else { return }
                if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 300 {
                    close()
                } else {
                    withAnimation(.spring) {
                        offset = .zero
                        pull = 0
                    }
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
