import OpenGrindKit
import SwiftUI

/// Someone's profile: photos, details, and what you can do with it.
struct ProfileScreen: View {
    let profileID: ProfileID
    /// The grid tile, shown while the full profile loads.
    var preview: GridProfile?
    /// Opened from the chat with this profile: "Message" goes back to it.
    var isFromChat = false
    /// The page on screen in a ``ProfilePager``, or a profile on its own. Only
    /// that one loads (and counts as viewed) and shows its name and menu in the
    /// navigation bar; its neighbours wait with the grid's data.
    var isCurrentPage = true

    @Environment(AccountSession.self) private var session
    @State private var model: ProfileModel?

    var body: some View {
        Group {
            if let model {
                ProfileContent(model: model, isFromChat: isFromChat, isCurrentPage: isCurrentPage)
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
    let isCurrentPage: Bool

    @Environment(AccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoViewerPresenter.self) private var photoViewer: PhotoViewerPresenter?
    @State private var selectedPhoto: String?
    @State private var isConfirmingBlock = false
    @State private var isConfirmingHide = false
    @State private var isReporting = false
    @State private var isShowingMutualTap = false
    /// Blocked from the report sheet: leave once it closes.
    @State private var hasBlocked = false

    private var name: String {
        Formatting.name(model.profile?.displayName)
    }

    var body: some View {
        Group {
            if let profile = model.profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        photos
                        ProfileDetails(profile: profile, catalogs: session.catalogs)
                            .padding(.horizontal)
                            .padding(.vertical, 20)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !model.isMe { actionBar(profile) }
                }
            } else if let failure = model.state.failure {
                FailureView(failure: failure) { await model.load() }
            } else {
                LoadingView()
            }
        }
        // Pushed from Messages or Interest; from the grid it's full screen anyway.
        .toolbar(model.isMe ? .automatic : .hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Pages next to the current one leave the bar to it.
            if isCurrentPage {
                ToolbarItem(placement: .principal) {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                if !model.isMe, model.profile != nil {
                    ToolbarItem(placement: .primaryAction) { safetyMenu }
                }
            }
        }
        .task(id: isCurrentPage) {
            if isCurrentPage { await model.loadIfNeeded() }
        }
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
                hasBlocked = try await model.report(report, alsoBlock: alsoBlock)
            }
        }
        .alert("You Tapped Each Other", isPresented: $isShowingMutualTap) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(name) tapped you too. Say hi!")
        }
        .failureAlert($model.actionFailure)
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
    private var photos: some View {
        let photos = visiblePhotos
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if photos.isEmpty {
                    ImagePlaceholder()
                } else {
                    // Up and down, as sideways goes to the next profile.
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(photos) { photo in
                                Button {
                                    photoViewer?.show(
                                        photos.map { MediaURL.profileImage($0.mediaHash, size: .full) },
                                        at: photos.firstIndex(of: photo) ?? 0)
                                } label: {
                                    RemoteImage(
                                        url: MediaURL.profileImage(photo.mediaHash, size: .full), pointSize: 500
                                    )
                                    .overlay(alignment: .bottomLeading) {
                                        if photo.isPendingReview { PendingReviewBadge() }
                                    }
                                }
                                .buttonStyle(.plain)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .clipped()
                                .accessibilityLabel(
                                    "Photo \((photos.firstIndex(of: photo) ?? 0) + 1) of \(photos.count)"
                                )
                                .accessibilityHint("Shows the photo full screen.")
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $selectedPhoto)
                    .scrollIndicators(.hidden)
                    .overlay(alignment: .trailing) {
                        if photos.count > 1 {
                            PhotoPageDots(photos: photos, selected: selectedPhoto ?? photos[0].id)
                        }
                    }
                }
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
                model.actionFailure = Failure(error)
            }
        }
    }
}

/// Which of the profile's photos is shown, as dots down the side.
private struct PhotoPageDots: View {
    let photos: [ProfilePhoto]
    let selected: String

    var body: some View {
        VStack(spacing: 6) {
            ForEach(photos) { photo in
                Circle()
                    .fill(photo.id == selected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.45)))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .background(.black.opacity(0.25), in: .capsule)
        .padding(.trailing, 8)
        .animation(.default, value: selected)
        // VoiceOver reads each photo's position instead.
        .accessibilityHidden(true)
    }
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
