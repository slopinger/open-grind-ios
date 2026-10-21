import OpenGrindKit
import SwiftUI

/// Photos full screen: swipe between them, pinch or double-tap to zoom.
struct PhotoViewer: View {
    let urls: [URL]
    @State var selection: Int
    /// False for view-once photos.
    var storesOnDisk = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $selection) {
            ForEach(urls.indices, id: \.self) { index in
                ZoomablePhoto(url: urls[index], storesOnDisk: storesOnDisk)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .always : .never))
        .background(.black)
        .ignoresSafeArea()
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

private struct ZoomablePhoto: View {
    let url: URL
    let storesOnDisk: Bool

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        RemoteImage(url: url, pointSize: 1024, contentMode: .fit, storesOnDisk: storesOnDisk)
            .scaleEffect(scale)
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

    private func reset() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
    }
}
