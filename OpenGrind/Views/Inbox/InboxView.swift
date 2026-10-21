import OpenGrindKit
import SwiftUI

/// Your conversations, newest first, with pinned ones on top.
struct InboxView: View {
    @Environment(AccountSession.self) private var session
    @State private var path: [Route] = []
    @State private var searchText = ""
    @State private var pendingDelete: Conversation?
    @State private var isShowingLockedInfo = false

    private var inbox: InboxModel { session.inbox }

    private var visibleConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return inbox.conversations }
        return inbox.conversations.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        @Bindable var inbox = inbox
        NavigationStack(path: $path) {
            content
                .navigationTitle("Messages")
                .searchable(text: $searchText, prompt: "Search Names")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { filterMenu }
                }
                .routeDestinations()
                .confirmationDialog(
                    "Delete Conversation?", isPresented: $pendingDelete.isPresent(), titleVisibility: .visible,
                    presenting: pendingDelete
                ) { conversation in
                    Button("Delete", role: .destructive) {
                        Task { await inbox.delete(conversation) }
                    }
                } message: { conversation in
                    Text(
                        "The conversation with \(conversation.name) is removed from your inbox. They keep their copy."
                    )
                }
                .alert("Subscription Required", isPresented: $isShowingLockedInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Grindr only shows this conversation with a paid subscription.")
                }
                .failureAlert($inbox.actionFailure)
        }
        .task { await inbox.loadIfNeeded() }
    }

    private var content: some View {
        let visible = visibleConversations
        return LoadStateView(inbox.state, isEmpty: inbox.conversations.isEmpty) {
            await inbox.refresh()
        } content: {
            list(visible)
                .overlay {
                    if inbox.conversations.isEmpty {
                        emptyState
                    } else if visible.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
        }
    }

    private func list(_ conversations: [Conversation]) -> some View {
        List {
            ForEach(conversations) { conversation in
                row(conversation)
                    .task { await inbox.loadMoreIfNeeded(after: conversation) }
            }
            if inbox.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await inbox.refresh() }
        .animation(.default, value: conversations.map(\.id))
    }

    private func pinButton(_ conversation: Conversation) -> some View {
        Button(
            conversation.isPinned ? "Unpin" : "Pin",
            systemImage: conversation.isPinned ? "pin.slash" : "pin"
        ) {
            Task { await inbox.setPinned(conversation, !conversation.isPinned) }
        }
    }

    private func muteButton(_ conversation: Conversation) -> some View {
        Button(
            conversation.isMuted ? "Unmute" : "Mute",
            systemImage: conversation.isMuted ? "bell" : "bell.slash"
        ) {
            Task { await inbox.setMuted(conversation, !conversation.isMuted) }
        }
    }

    @ViewBuilder
    private func row(_ conversation: Conversation) -> some View {
        let otherID = conversation.otherProfileID(me: session.profileID)
        Group {
            if conversation.isLocked {
                Button {
                    isShowingLockedInfo = true
                } label: {
                    ConversationRow(conversation: conversation, me: session.profileID)
                }
                .foregroundStyle(.primary)
            } else if let otherID {
                NavigationLink(value: Route.chat(otherID)) {
                    ConversationRow(conversation: conversation, me: session.profileID)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = conversation }
            muteButton(conversation)
                .tint(.indigo)
        }
        .swipeActions(edge: .leading) {
            pinButton(conversation)
                .tint(.orange)
        }
        .contextMenu {
            pinButton(conversation)
            muteButton(conversation)
            if let otherID, !conversation.isLocked {
                Button("View Profile", systemImage: "person.crop.circle") {
                    path.append(.profile(otherID))
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = conversation }
        }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Unread", systemImage: "envelope.badge", isOn: filterBinding(\.unreadOnly))
            Toggle("Favorites", systemImage: "star", isOn: filterBinding(\.favoritesOnly))
            Toggle("Online Now", systemImage: "circle.fill", isOn: filterBinding(\.onlineNowOnly))
        } label: {
            Label(
                "Filter",
                systemImage: inbox.filter.isDefault
                    ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .menuActionDismissBehavior(.disabled)
    }

    private func filterBinding(_ keyPath: WritableKeyPath<InboxFilter, Bool>) -> Binding<Bool> {
        Binding {
            inbox.filter[keyPath: keyPath]
        } set: { isOn in
            var filter = inbox.filter
            filter[keyPath: keyPath] = isOn
            Task { await inbox.apply(filter) }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if inbox.filter.isDefault {
            ContentUnavailableView {
                Label("No Messages", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Conversations you start or receive appear here.")
            }
        } else {
            ContentUnavailableView {
                Label("No Matching Conversations", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Show All") {
                    Task { await inbox.apply(InboxFilter()) }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// An inbox entry: photo, name, last message and time.
struct ConversationRow: View {
    let conversation: Conversation
    let me: ProfileID

    private var isUnread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(
                photoHash: conversation.participant?.photoHash, size: 56,
                isOnline: conversation.participant?.isOnline() ?? false, isLocked: conversation.isLocked
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Formatting.name(conversation.name))
                        .font(.body.weight(isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    if conversation.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Color.brand)
                            .accessibilityLabel("Favorite")
                    }
                    Spacer(minLength: 8)
                    Text(Formatting.listTime(conversation.lastActivity))
                        .font(.subheadline)
                        .foregroundStyle(isUnread ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                }
                HStack(alignment: .top, spacing: 6) {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(isUnread ? Color.primary : Color.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }
                    if conversation.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Muted")
                    }
                    if isUnread {
                        UnreadBadge(count: conversation.unreadCount, isMuted: conversation.isMuted)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var previewText: String {
        if conversation.isLocked {
            return String(localized: "Unlock with a subscription")
        }
        guard let preview = conversation.preview else { return "" }
        let body = MessageText.preview(
            kind: preview.kind, text: preview.text, isUnsent: preview.isUnsent)
        return preview.senderID == me ? String(localized: "You: \(body)") : body
    }
}

/// The unread count in a conversation row.
struct UnreadBadge: View {
    let count: Int
    var isMuted = false

    var body: some View {
        BrandBadge(Text(count, format: .number), isMuted: isMuted)
            .accessibilityLabel("\(count) unread")
    }
}

/// How messages are described where only text fits.
enum MessageText {
    static func preview(kind: MessageKind, text: String?, isUnsent: Bool) -> String {
        if isUnsent { return String(localized: "Message unsent") }
        switch kind {
        case .text: return text ?? ""
        case .image: return String(localized: "📷 Photo")
        case .expiringImage: return String(localized: "📷 Expiring photo")
        case .location: return String(localized: "📍 Location")
        case .gaymoji: return String(localized: "Sticker")
        case .giphy: return String(localized: "GIF")
        case .profilePhotoReply:
            return text.map { String(localized: "Replied to a photo: \($0)") }
                ?? String(localized: "Replied to a photo")
        case .audio: return String(localized: "🎤 Voice message")
        case .video, .privateVideo: return String(localized: "🎥 Video")
        case .album, .expiringAlbum, .expiringAlbumV2: return String(localized: "🖼️ Album")
        case .videoCall: return String(localized: "📞 Video call")
        default: return text ?? String(localized: "Message")
        }
    }
}
