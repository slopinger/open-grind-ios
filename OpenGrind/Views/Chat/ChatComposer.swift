import OpenGrindKit
import PhotosUI
import SwiftUI

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
            guard let photo = try await PhotoEncoder.jpeg(from: item) else {
                photoFailure = .unexpected("unreadable photo")
                return
            }
            sentCount += 1
            await chat.sendPhoto(photo.data)
        } catch {
            photoFailure = Failure(error)
        }
    }
}
