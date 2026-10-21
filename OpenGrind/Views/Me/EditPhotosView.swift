import OpenGrindKit
import PhotosUI
import SwiftUI

/// Your profile photos: add, reorder and delete them. Changes are saved right away.
struct EditPhotosView: View {
    @Environment(AccountSession.self) private var session
    @State private var isPickingPhotos = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingDelete: ProfilePhoto?
    @State private var encodingFailure: Failure?
    /// Picked photos are being prepared for upload.
    @State private var isPreparing = false

    private var me: MeModel { session.me }
    private var photos: [ProfilePhoto] { me.profile?.photos ?? [] }

    var body: some View {
        @Bindable var me = me
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(photos) { photo in
                        tile(photo)
                    }
                    if isPreparing || me.isUploadingPhotos {
                        PhotoSlot {
                            ProgressView()
                                .accessibilityLabel("Uploading photos")
                        }
                    } else if me.remainingPhotoSlots > 0 {
                        addButton
                    }
                }
                Text(
                    "Your first photo is your main photo. Tap a photo to move or delete it. New photos are only visible to you until Grindr approves them."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: photos)
        // The modifier rather than a PhotosPicker view: PhotosPicker's label closure is
        // @Sendable and nonisolated, so it can't build this screen's main-actor views.
        .photosPicker(
            isPresented: $isPickingPhotos, selection: $pickerItems, maxSelectionCount: max(me.remainingPhotoSlots, 1),
            matching: .images, preferredItemEncoding: .compatible
        )
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task { await upload(items) }
        }
        .confirmationDialog(
            "Delete Photo?", isPresented: $pendingDelete.isPresent(), titleVisibility: .visible,
            presenting: pendingDelete
        ) { photo in
            Button("Delete Photo", role: .destructive) { Task { await me.deletePhoto(photo) } }
        } message: { _ in
            Text("The photo is removed from your profile and from Grindr.")
        }
        .failureAlert($me.actionFailure)
        .failureAlert($encodingFailure)
        .sensoryFeedback(.success, trigger: photos.count) { old, new in new > old }
        .task { await me.loadIfNeeded() }
    }

    private func tile(_ photo: ProfilePhoto) -> some View {
        let index = photos.firstIndex(of: photo) ?? 0
        return Menu {
            if index > 0 {
                Button("Make Main Photo", systemImage: "star") { move(photo, to: 0) }
                Button("Move Earlier", systemImage: "arrow.backward") { move(photo, to: index - 1) }
            }
            if index < photos.count - 1 {
                Button("Move Later", systemImage: "arrow.forward") { move(photo, to: index + 1) }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = photo }
        } label: {
            PhotoSlot {
                RemoteImage(url: MediaURL.profileImage(photo.mediaHash, size: .thumbnail), pointSize: 130)
            }
            .overlay(alignment: .topLeading) {
                if index == 0 {
                    Text("Main")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.brandForeground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.brand, in: .capsule)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if photo.isPendingReview {
                    Image(systemName: "clock")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                        .background(.ultraThinMaterial, in: .circle)
                        .padding(6)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(photo, index: index))
        .accessibilityHint("Shows options to move or delete the photo.")
    }

    private var addButton: some View {
        Button {
            isPickingPhotos = true
        } label: {
            PhotoSlot {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Photos")
    }

    private func accessibilityLabel(_ photo: ProfilePhoto, index: Int) -> Text {
        var label = String(localized: "Photo \(index + 1) of \(photos.count)")
        if index == 0 { label += ", " + String(localized: "main photo") }
        if photo.isPendingReview { label += ", " + String(localized: "in review") }
        return Text(label)
    }

    private func move(_ photo: ProfilePhoto, to destination: Int) {
        Task { await me.movePhoto(photo, to: destination) }
    }

    /// Prepares the picked photos, then adds the ones that could be read in one go.
    private func upload(_ items: [PhotosPickerItem]) async {
        isPreparing = true
        defer { isPreparing = false }
        var jpegs: [JPEGPhoto] = []
        for item in items {
            do {
                if let jpeg = try await PhotoEncoder.jpeg(from: item) {
                    jpegs.append(jpeg)
                } else {
                    encodingFailure = .unexpected("unreadable photo")
                }
            } catch {
                encodingFailure = Failure(error)
            }
        }
        await me.addPhotos(jpegs)
    }
}

/// A square tile in the photo grid.
private struct PhotoSlot<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12, style: .continuous))
    }
}
