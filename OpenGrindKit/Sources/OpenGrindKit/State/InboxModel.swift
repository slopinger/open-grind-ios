import Foundation
import Observation

/// The inbox: conversations, kept current by realtime events.
@MainActor
@Observable
public final class InboxModel {
    /// Pinned first, then most recent first.
    public private(set) var conversations: [Conversation] = [] {
        didSet {
            unreadByConversation = Dictionary(
                conversations.map { ($0.id, $0.unreadCount) }, uniquingKeysWith: { first, _ in first })
        }
    }
    /// For looking up one conversation's count, e.g. on every grid tile.
    private var unreadByConversation: [String: Int] = [:]
    public private(set) var state: LoadState = .idle
    public private(set) var isLoadingMore = false
    public private(set) var filter = InboxFilter()
    /// The last action that failed (pin, mute, delete), to show in an alert.
    public var actionFailure: Failure?
    /// The conversation on screen; it does not collect unread messages.
    public var openConversationID: String?

    @ObservationIgnored weak var session: AccountSession?
    @ObservationIgnored private let api: GrindrAPI
    @ObservationIgnored private let me: ProfileID
    @ObservationIgnored private var nextPage: Int?
    @ObservationIgnored private var generation = 0
    /// Change events come in bursts; the inbox is reloaded once they settle.
    @ObservationIgnored private let refreshAfterChanges = Debouncer(.milliseconds(600))

    init(api: GrindrAPI, me: ProfileID) {
        self.api = api
        self.me = me
    }

    /// Unread messages across the inbox, for the tab badge.
    public var unreadCount: Int {
        conversations.filter { !$0.isMuted }.reduce(0) { $0 + $1.unreadCount }
    }

    /// Unread messages from `profileID`, if the inbox has loaded that conversation.
    public func unreadCount(from profileID: ProfileID) -> Int? {
        unreadByConversation[Conversation.id(between: me, and: profileID)]
    }

    public var canLoadMore: Bool { nextPage != nil }

    public func loadIfNeeded() async {
        guard state.needsLoad else { return }
        await refresh()
    }

    public func refresh() async {
        generation += 1
        let generation = generation
        if conversations.isEmpty { state = .loading }
        do {
            let page = try await api.inbox(page: 1, filter: filter)
            guard generation == self.generation else { return }
            conversations = Self.sorted(page.conversations)
            nextPage = page.nextPage
            state = .loaded
        } catch {
            guard generation == self.generation else { return }
            if conversations.isEmpty || state != .loaded {
                state = .failed(Failure(error))
            }
        }
    }

    public func apply(_ filter: InboxFilter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        conversations = []
        nextPage = nil
        await refresh()
    }

    public func loadMoreIfNeeded(after conversation: Conversation) async {
        guard let index = conversations.lastIndex(where: { $0.id == conversation.id }),
            index >= conversations.count - 5
        else { return }
        await loadMore()
    }

    public func loadMore() async {
        guard !isLoadingMore, let page = nextPage, state == .loaded else { return }
        let generation = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let next = try? await api.inbox(page: page, filter: filter), generation == self.generation
        else {
            return
        }
        conversations = Self.sorted(
            conversations + next.conversations.uniqued(excluding: conversations.map(\.id)))
        nextPage = next.nextPage
    }

    public func conversation(_ id: String) -> Conversation? {
        conversations.first { $0.id == id }
    }

    // MARK: Actions

    public func setPinned(_ conversation: Conversation, _ isPinned: Bool) async {
        await update(
            conversation.id, { $0.isPinned = isPinned },
            request: { try await self.api.setPinned(conversation.id, isPinned) })
    }

    public func setMuted(_ conversation: Conversation, _ isMuted: Bool) async {
        await update(
            conversation.id, { $0.isMuted = isMuted },
            request: { try await self.api.setMuted(conversation.id, isMuted) })
    }

    /// Removes the conversation from your inbox. The other side keeps it.
    public func delete(_ conversation: Conversation) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        let removed = conversations.remove(at: index)
        do {
            try await api.deleteConversation(conversation.id)
        } catch {
            conversations = Self.sorted(conversations + [removed])
            actionFailure = Failure(error)
        }
    }

    /// Clears the unread badge of a conversation that was just read.
    func markRead(_ conversationID: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].unreadCount = 0
    }

    /// Shows a message you just sent at the top of the inbox.
    func noteSent(_ message: Message) {
        apply(message, isIncoming: false)
    }

    private func update(
        _ id: String, _ change: (inout Conversation) -> Void, request: () async throws -> Void
    ) async {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let original = conversations[index]
        change(&conversations[index])
        conversations = Self.sorted(conversations)
        do {
            try await request()
        } catch {
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index] = original
                conversations = Self.sorted(conversations)
            }
            actionFailure = Failure(error)
        }
    }

    // MARK: Updates from elsewhere

    func remove(conversationID: String) {
        conversations.removeAll { $0.id == conversationID }
    }

    func setFavorite(_ profileID: ProfileID, _ isFavorite: Bool) {
        let id = Conversation.id(between: me, and: profileID)
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isFavorite = isFavorite
    }

    func handle(_ event: RealtimeEvent) {
        switch event {
        case .message(let message):
            apply(message, isIncoming: message.senderID != me)
        case .conversationRead(let conversationID, let reader, _) where reader == me:
            markRead(conversationID)
        case .conversationsDeleted(let ids):
            conversations.removeAll { ids.contains($0.id) }
        case .conversationsChanged, .inboxInvalidated:
            scheduleRefresh()
        default:
            break
        }
    }

    private func apply(_ message: Message, isIncoming: Bool) {
        guard let index = conversations.firstIndex(where: { $0.id == message.conversationID }) else {
            // A new conversation: the inbox entry has details a message lacks.
            if message.retractedMessageID == nil { scheduleRefresh() }
            return
        }
        if let retracted = message.retractedMessageID {
            if conversations[index].preview?.messageID == retracted {
                conversations[index].preview?.isUnsent = true
            }
            return
        }
        // Reactions arrive as updates of older messages.
        guard message.date >= conversations[index].lastActivity else { return }
        // The same message again, e.g. delivered twice around a reconnect.
        let isRepeat = conversations[index].preview?.messageID == message.id
        conversations[index].lastActivity = message.date
        conversations[index].preview = MessagePreview(
            messageID: message.id, kind: message.content.kind, text: message.previewText,
            senderID: message.senderID,
            isUnsent: message.content == .unsent)
        if isIncoming, !isRepeat, message.content != .unsent, openConversationID != message.conversationID {
            conversations[index].unreadCount += 1
        }
        conversations = Self.sorted(conversations)
    }

    private func scheduleRefresh() {
        refreshAfterChanges.schedule { [weak self] in await self?.refresh() }
    }

    static func sorted(_ conversations: [Conversation]) -> [Conversation] {
        conversations.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastActivity > rhs.lastActivity
        }
    }
}

extension Message.Content {
    /// The API's type name for this content.
    public var kind: MessageKind {
        switch self {
        case .text: .text
        case .image: .image
        case .expiringImage: .expiringImage
        case .location: .location
        case .gaymoji: .gaymoji
        case .giphy: .giphy
        case .profilePhotoReply: .profilePhotoReply
        case .audio: .audio
        case .video: .video
        case .album: .album
        case .unsent: .text
        case .unsupported(let kind): kind
        }
    }
}
