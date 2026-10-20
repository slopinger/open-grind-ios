import MapKit
import OpenGrindKit
import SwiftUI

/// One message: its bubble, delivery state and actions.
struct MessageRow: View {
    let chat: ChatModel
    let item: ChatModel.Item
    /// The first message after one from the other side.
    let startsGroup: Bool
    let endsGroup: Bool
    let showsReadReceipt: Bool
    let openImage: (URL) -> Void

    @State private var isConfirmingUnsend = false

    private var isOutgoing: Bool { chat.isOutgoing(item) }
    private var message: Message { item.message }

    var body: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 6) {
                if isOutgoing { Spacer(minLength: 48) }
                if item.delivery == .failed { failedButton }
                MessageBubble(item: item, isOutgoing: isOutgoing, openImage: openImage)
                    .overlay(alignment: isOutgoing ? .bottomLeading : .bottomTrailing) {
                        if !message.reactions.isEmpty { reactionBadge }
                    }
                    .opacity(item.delivery == .sending ? 0.6 : 1)
                    .contextMenu { menu }
                if !isOutgoing { Spacer(minLength: 48) }
            }
            if showsReadReceipt || item.delivery == .failed || endsGroup {
                footer
            }
        }
        .padding(.top, startsGroup ? 8 : 0)
        .padding(.bottom, message.reactions.isEmpty ? 0 : 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions { accessibilityActions }
        .confirmationDialog(
            "Unsend Message?", isPresented: $isConfirmingUnsend, titleVisibility: .visible
        ) {
            Button("Unsend", role: .destructive) { Task { await chat.unsend(item) } }
        } message: {
            Text("The message is removed for both of you.")
        }
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            switch item.delivery {
            case .failed:
                Text("Not Delivered")
                    .foregroundStyle(.red)
            case .sending:
                Text("Sending…")
            case .sent:
                if showsReadReceipt {
                    Text("Read")
                } else {
                    Text(message.date, format: .dateTime.hour().minute())
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    private var failedButton: some View {
        Menu {
            Button("Try Again", systemImage: "arrow.clockwise") { Task { await chat.retry(item) } }
            Button("Delete", systemImage: "trash", role: .destructive) { chat.discard(item) }
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Not delivered")
    }

    private var reactionBadge: some View {
        Image(systemName: "heart.fill")
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(5)
            .background(.red, in: .circle)
            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            .offset(x: isOutgoing ? -8 : 8, y: 10)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var menu: some View {
        if case .text(let text) = message.content {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
        if item.delivery == .sent, message.content != .unsent {
            if !isOutgoing, !chat.hasHeart(item) {
                Button("Heart", systemImage: "heart") { Task { await chat.heart(item) } }
            }
            if isOutgoing {
                Button("Unsend", systemImage: "arrow.uturn.backward") { isConfirmingUnsend = true }
            }
            Button("Delete for Me", systemImage: "trash", role: .destructive) {
                Task { await chat.deleteForMe(item) }
            }
        }
    }

    @ViewBuilder
    private var accessibilityActions: some View {
        if item.delivery == .failed {
            Button("Try Again") { Task { await chat.retry(item) } }
            Button("Delete") { chat.discard(item) }
        }
        if item.delivery == .sent, message.content != .unsent {
            if !isOutgoing, !chat.hasHeart(item) {
                Button("Heart") { Task { await chat.heart(item) } }
            }
            if isOutgoing {
                Button("Unsend") { isConfirmingUnsend = true }
            }
            Button("Delete for Me") { Task { await chat.deleteForMe(item) } }
        }
    }

    private var accessibilityLabel: Text {
        let sender = isOutgoing ? String(localized: "You") : (chat.name ?? String(localized: "Them"))
        let body = MessageText.preview(
            kind: message.content.kind, text: message.previewText, isUnsent: message.content == .unsent)
        var parts = [sender, body, message.date.formatted(date: .omitted, time: .shortened)]
        if !message.reactions.isEmpty { parts.append(String(localized: "Hearted")) }
        if showsReadReceipt { parts.append(String(localized: "Read")) }
        switch item.delivery {
        case .sending: parts.append(String(localized: "Sending"))
        case .failed: parts.append(String(localized: "Not delivered"))
        case .sent: break
        }
        return Text(parts.joined(separator: ", "))
    }
}

/// The content of a message, in a bubble where it has one.
private struct MessageBubble: View {
    let item: ChatModel.Item
    let isOutgoing: Bool
    let openImage: (URL) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let data = item.localPhoto, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 220, height: 220 * min(image.size.height / max(image.size.width, 1), 1.5))
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.message.content {
        case .text(let text):
            textBubble(Text(text))
        case .unsent:
            textBubble(Text("Message unsent").italic(), isMuted: true)
        case .image(let url, let width, let height):
            photo(url: url, aspectRatio: aspectRatio(width, height))
        case .giphy(let url, let width, let height):
            photo(url: url, aspectRatio: aspectRatio(width, height), opensViewer: false)
        case .gaymoji(let hash):
            RemoteImage(url: MediaURL.gaymoji(hash), pointSize: 120, contentMode: .fit)
                .frame(width: 120, height: 120)
                .accessibilityLabel(MediaURL.gaymojiLabel(hash))
        case .profilePhotoReply(let hash, let text):
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                RemoteImage(url: MediaURL.profileImage(hash, size: .thumbnail), pointSize: 96)
                    .frame(width: 96, height: 96)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .opacity(0.85)
                textBubble(Text(text))
            }
        case .location(let latitude, let longitude):
            locationBubble(latitude: latitude, longitude: longitude)
        case .expiringImage(let url):
            if let url {
                Button {
                    openImage(url)
                } label: {
                    unsupportedBubble("Expiring Photo", systemImage: "timer", detail: "Tap to view")
                }
                .buttonStyle(.plain)
            } else {
                unsupportedBubble("Expiring Photo", systemImage: "timer", detail: "No longer available")
            }
        case .audio:
            unsupportedBubble(
                "Voice Message", systemImage: "waveform", detail: "Open Grind can't play these yet")
        case .video:
            unsupportedBubble("Video", systemImage: "video", detail: "Open Grind can't play these yet")
        case .album(_, let isViewable):
            unsupportedBubble(
                "Album", systemImage: "photo.stack",
                detail: isViewable ? "Albums aren't supported yet" : "Shared privately")
        case .unsupported(let kind):
            if kind == .image {
                // A photo still being uploaded without a local copy.
                ImagePlaceholder()
                    .frame(width: 220, height: 220)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
            } else {
                unsupportedBubble("Unsupported Message", systemImage: "questionmark.bubble", detail: nil)
            }
        }
    }

    private func textBubble(_ text: Text, isMuted: Bool = false) -> some View {
        text
            .foregroundStyle(isOutgoing && !isMuted ? Color.brandForeground : Color.primary)
            .opacity(isMuted ? 0.6 : 1)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(bubbleColor, in: .rect(cornerRadius: 18, style: .continuous))
            .textSelection(.enabled)
    }

    private var bubbleColor: Color {
        isOutgoing ? .brand : Color(.secondarySystemFill)
    }

    private func photo(url: URL, aspectRatio: CGFloat, opensViewer: Bool = true) -> some View {
        Button {
            if opensViewer { openImage(url) }
        } label: {
            RemoteImage(url: url, pointSize: 440)
                .frame(width: 220, height: 220 / aspectRatio)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!opensViewer)
        .accessibilityLabel(opensViewer ? "Photo" : "GIF")
    }

    private func aspectRatio(_ width: Int?, _ height: Int?) -> CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 1 }
        // Very tall images are cropped rather than filling the screen.
        return max(CGFloat(width) / CGFloat(height), 2 / 3)
    }

    private func locationBubble(latitude: Double, longitude: Double) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return Button {
            if let url = URL(
                string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(latitude),\(longitude)")
            {
                openURL(url)
            }
        } label: {
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)),
                interactionModes: []
            ) {
                Marker("", coordinate: coordinate)
            }
            .frame(width: 220, height: 150)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Location")
        .accessibilityHint("Opens in Maps.")
    }

    private func unsupportedBubble(
        _ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail).font(.caption).opacity(0.75)
                }
            }
        }
        .foregroundStyle(isOutgoing ? Color.brandForeground : Color.primary)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(bubbleColor, in: .rect(cornerRadius: 18, style: .continuous))
    }
}
