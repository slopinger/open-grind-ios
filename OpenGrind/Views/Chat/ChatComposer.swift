import ImageIO
import OpenGrindKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The message field, photo button and send button under a chat.
struct ChatComposer: View {
    @Bindable var chat: ChatModel
    var isFocused: FocusState<Bool>.Binding

    @State private var photoItem: PhotosPickerItem?
    @State private var photoFailure: Failure?
    @State private var sentCount = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                Image(systemName: "photo")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Send Photo")

            TextField("Message", text: $chat.draft, axis: .vertical)
                .lineLimit(1...6)
                .focused(isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemFill), in: .rect(cornerRadius: 20, style: .continuous))

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        chat.canSendDraft ? Color.brandForeground : Color.secondary,
                        chat.canSendDraft ? Color.brand : Color(.tertiarySystemFill))
            }
            .disabled(!chat.canSendDraft)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await sendPhoto(item) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sentCount)
        .failureAlert($photoFailure)
    }

    private func send() {
        guard chat.canSendDraft else { return }
        sentCount += 1
        Task { await chat.sendDraft() }
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                let jpeg = await ChatPhotoEncoder.jpeg(from: data)
            else {
                photoFailure = .unexpected("unreadable photo")
                return
            }
            sentCount += 1
            await chat.sendPhoto(jpeg, contentType: "image/jpeg")
        } catch {
            photoFailure = Failure(error)
        }
    }
}

/// Prepares photos for chat: at most 2048 pixels on the long side, JPEG, and
/// without metadata such as the location the photo was taken at.
enum ChatPhotoEncoder {
    static let maxPixelSize = 2048

    @concurrent
    static func jpeg(from data: Data) async -> Data? {
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
        return output as Data
    }
}
