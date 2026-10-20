import OpenGrindKit
import SwiftUI

/// Someone's profile: photos, details, and what you can do with it.
struct ProfileScreen: View {
    let profileID: ProfileID
    /// The grid tile, shown while the full profile loads.
    var preview: GridProfile?
    /// Opened from the chat with this profile: "Message" goes back to it.
    var isFromChat = false

    @Environment(AccountSession.self) private var session
    @State private var model: ProfileModel?

    var body: some View {
        Group {
            if let model {
                ProfileContent(model: model, isFromChat: isFromChat)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil {
                model = ProfileModel(
                    profileID: profileID, session: session, preview: preview.map { Profile($0) })
            }
        }
    }
}

private struct ProfileContent: View {
    @Bindable var model: ProfileModel
    let isFromChat: Bool

    @Environment(AccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: String?
    @State private var viewerPhoto: PhotoSelection?
    @State private var isConfirmingBlock = false
    @State private var isConfirmingHide = false
    @State private var isReporting = false
    @State private var isShowingMutualTap = false
    @State private var removalFailure: Failure?
    /// Blocked from the report sheet: leave once it closes.
    @State private var hasBlocked = false

    private var name: String {
        model.profile?.displayName ?? String(localized: "No name")
    }

    var body: some View {
        Group {
            if let profile = model.profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        photos(profile)
                        ProfileDetails(profile: profile, me: session.me)
                            .padding(.horizontal)
                            .padding(.vertical, 20)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom) {
                    if !model.isMe { actionBar(profile) }
                }
            } else if let failure = model.state.failure {
                FailureView(failure: failure) { await model.load() }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            if !model.isMe, model.profile != nil {
                ToolbarItem(placement: .primaryAction) { safetyMenu }
            }
        }
        .task { await model.load() }
        .confirmationDialog(
            "Block \(name)?", isPresented: $isConfirmingBlock, titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) { remove { try await model.block() } }
        } message: {
            Text(
                "You won't see each other anymore, and your conversation is removed. You can unblock in Profile > Blocked."
            )
        }
        .confirmationDialog("Hide \(name)?", isPresented: $isConfirmingHide, titleVisibility: .visible) {
            Button("Hide from Grid", role: .destructive) { remove { try await model.hide() } }
        } message: {
            Text("They won't appear in your grid anymore. They can still message you.")
        }
        .sheet(
            isPresented: $isReporting,
            onDismiss: {
                if hasBlocked { dismiss() }
            }
        ) {
            ReportSheet(name: name) { report, alsoBlock in
                try await model.report(report)
                if alsoBlock {
                    try await model.block()
                    hasBlocked = true
                }
            }
        }
        .fullScreenCover(item: $viewerPhoto) { selection in
            let photos = visiblePhotos
            PhotoViewer(
                urls: photos.map { MediaURL.profileImage($0.mediaHash, size: .full) },
                selection: photos.firstIndex { $0.id == selection.id } ?? 0)
        }
        .alert("You Tapped Each Other", isPresented: $isShowingMutualTap) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(name) tapped you too. Say hi!")
        }
        .failureAlert($model.actionFailure)
        .failureAlert($removalFailure)
        .sensoryFeedback(.success, trigger: model.sentTap) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: model.profile?.isFavorite)
        .onChange(of: model.isMutualTap) { _, isMutual in
            if isMutual { isShowingMutualTap = true }
        }
    }

    // MARK: Photos

    /// Photos waiting for moderation are only yours to see.
    private var visiblePhotos: [ProfilePhoto] {
        (model.profile?.photos ?? []).filter { !$0.isPendingReview || model.isMe }
    }

    @ViewBuilder
    private func photos(_ profile: Profile) -> some View {
        let photos = visiblePhotos
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if photos.isEmpty {
                    ImagePlaceholder()
                } else {
                    TabView(selection: $selectedPhoto) {
                        ForEach(photos) { photo in
                            Button {
                                viewerPhoto = PhotoSelection(id: photo.id)
                            } label: {
                                RemoteImage(
                                    url: MediaURL.profileImage(photo.mediaHash, size: .full), pointSize: 500
                                )
                                .overlay(alignment: .bottomLeading) {
                                    if photo.isPendingReview { PendingReviewBadge() }
                                }
                            }
                            .buttonStyle(.plain)
                            .tag(Optional(photo.id))
                            .accessibilityLabel(
                                "Photo \((photos.firstIndex(of: photo) ?? 0) + 1) of \(photos.count)"
                            )
                            .accessibilityHint("Shows the photo full screen.")
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
                }
            }
            .overlay(alignment: .top) {
                // Keeps the navigation bar legible over light photos.
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .allowsHitTesting(false)
            }
            .clipped()
    }

    // MARK: Actions

    private func actionBar(_ profile: Profile) -> some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(TapType.allCases) { type in
                    Button {
                        Task { await model.sendTap(type) }
                    } label: {
                        Text(verbatim: "\(type.emoji) \(type.localizedName)")
                    }
                }
            } label: {
                Image(systemName: model.sentTap == nil ? "flame" : "flame.fill")
                    .font(.title3)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(model.sentTap == nil ? Text("Tap") : Text("Tapped"))
            .accessibilityHint("Lets \(name) know you're interested.")

            Group {
                if isFromChat {
                    Button {
                        dismiss()
                    } label: {
                        messageLabel
                    }
                } else {
                    NavigationLink(value: Route.chat(model.profileID)) { messageLabel }
                }
            }
            .buttonStyle(.brandProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            Button {
                Task { await model.setFavorite(!profile.isFavorite) }
            } label: {
                Image(systemName: profile.isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .frame(width: 50, height: 50)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(profile.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var safetyMenu: some View {
        Menu {
            Button("Hide from Grid", systemImage: "eye.slash") { isConfirmingHide = true }
            Button("Block", systemImage: "hand.raised", role: .destructive) { isConfirmingBlock = true }
            Button("Report", systemImage: "exclamationmark.bubble", role: .destructive) {
                isReporting = true
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    private var messageLabel: some View {
        Label("Message", systemImage: "bubble.left.fill")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 38)
    }

    /// Blocks or hides, then leaves the screen: the profile is gone.
    private func remove(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                dismiss()
            } catch {
                removalFailure = Failure(error)
            }
        }
    }
}

/// Identifies the photo opened full screen.
private struct PhotoSelection: Identifiable {
    var id: String
}

/// Marks your own photos that moderation hasn't approved yet.
struct PendingReviewBadge: View {
    var body: some View {
        Label("In Review", systemImage: "clock")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(10)
    }
}

extension Profile {
    /// What the grid already knows about a profile.
    init(_ tile: GridProfile) {
        let thumbnail = "/images/thumb/320x320/"
        let photos: [ProfilePhoto] =
            if let url = tile.photoURL, url.host == "cdns.grindr.com", url.path.hasPrefix(thumbnail) {
                [ProfilePhoto(mediaHash: url.lastPathComponent)]
            } else {
                []
            }
        self.init(
            id: tile.id, displayName: tile.displayName, age: tile.age, distance: tile.distance,
            onlineUntil: tile.onlineUntil, lastSeen: tile.lastOnline, photos: photos,
            position: tile.position,
            isFavorite: tile.isFavorite, isVisiting: tile.isVisiting, unreadCount: tile.unreadCount)
    }
}
