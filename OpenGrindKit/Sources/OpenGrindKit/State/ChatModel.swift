import Foundation
import Observation

/// One conversation: its messages, sending, and live updates.
@MainActor
@Observable
public final class ChatModel: Identifiable {
    /// A message on screen, including ones still being sent.
    public struct Item: Identifiable, Hashable, Sendable {
        public enum Delivery: Hashable, Sendable {
            case sent
            case sending
            case failed
        }

        public var message: Message
        public var delivery: Delivery
        /// A photo being sent, shown until the server has it.
        public var localPhoto: Data?

        public var id: String { message.id }
    }

    public nonisolated let conversationID: String
    public nonisolated let otherProfileID: ProfileID
    public nonisolated var id: String { conversationID }

    public private(set) var name: String?
    public private(set) var profile: ConversationProfile?
    /// Oldest first.
    public private(set) var items: [Item] = []
    public private(set) var state: LoadState = .idle
    /// Loading earlier messages; after a failure they load again only when asked.
    public private(set) var olderState: LoadState = .idle
    public var hasOlderMessages: Bool { olderPageKey != nil }
    /// The other side has read everything up to this date.
    public private(set) var readByOtherUntil: Date?
    public private(set) var isOtherTyping = false
    public var draft = ""
    public var actionFailure: Failure?

    @ObservationIgnored weak var session: AccountSession?
    @ObservationIgnored private let api: GrindrAPI
    public nonisolated let me: ProfileID
    /// Where the next older page starts; `nil` at the start of the conversation.
    private var olderPageKey: String?
    /// What each message still sending or failed will send, by its local ID.
    @ObservationIgnored private var unsent: [String: Unsent] = [:]
    @ObservationIgnored private var typingReset: Task<Void, Never>?
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var lastMarkedRead: String?

    init(
        conversationID: String, otherProfileID: ProfileID, name: String?, api: GrindrAPI, me: ProfileID
    ) {
        self.conversationID = conversationID
        self.otherProfileID = otherProfileID
        self.name = name
        self.api = api
        self.me = me
    }

    public func isOutgoing(_ item: Item) -> Bool { item.message.senderID == me }

    /// The last of your messages the other side has read, for a "Read" label.
    public var lastReadOutgoingID: String? {
        guard let readByOtherUntil else { return nil }
        return items.last {
            isOutgoing($0) && $0.delivery == .sent && $0.message.date <= readByOtherUntil
        }?.id
    }

    public var canSendDraft: Bool {
        draft.nonBlank != nil
    }

    // MARK: Lifecycle

    public func appeared() {
        isVisible = true
        session?.inbox.openConversationID = conversationID
        markReadIfNeeded()
    }

    public func disappeared() {
        isVisible = false
        if session?.inbox.openConversationID == conversationID {
            session?.inbox.openConversationID = nil
        }
    }

    public func loadIfNeeded() async {
        guard state.needsLoad else { return }
        await reload()
    }

    /// Loads the newest page again, keeping messages still being sent.
    public func reload() async {
        if items.isEmpty { state = .loading }
        do {
            let page = try await api.messages(in: conversationID)
            profile = page.profile ?? profile
            name = page.profile?.name ?? name
            readByOtherUntil = page.lastRead
            let pending = items.filter { $0.delivery != .sent }
            items =
                Self.visible(page.messages.reversed()).map { Item(message: $0, delivery: .sent) } + pending
            olderPageKey = page.nextPageKey
            state = .loaded
            markReadIfNeeded()
        } catch {
            state = items.isEmpty ? .failed(Failure(error)) : .loaded
            if !items.isEmpty { actionFailure = Failure(error) }
        }
    }

    public func loadOlder() async {
        guard olderState != .loading, let key = olderPageKey else { return }
        olderState = .loading
        do {
            let page = try await api.messages(in: conversationID, pageKey: key)
            let older = Self.visible(page.messages.reversed()).uniqued(excluding: items.map(\.id))
            items.insert(contentsOf: older.map { Item(message: $0, delivery: .sent) }, at: 0)
            olderPageKey = page.nextPageKey
            olderState = .loaded
        } catch {
            olderState = .failed(Failure(error))
        }
    }

    // MARK: Sending

    public func sendDraft() async {
        guard let text = draft.nonBlank else { return }
        draft = ""
        await send(.text(text))
    }

    public func send(_ message: OutgoingMessage) async {
        let localID = "local-\(UUID().uuidString)"
        unsent[localID] = .message(message)
        items.append(
            Item(
                message: placeholder(localID, content: Self.optimisticContent(message)), delivery: .sending)
        )
        await deliver(localID)
    }

    /// Uploads a JPEG and sends it.
    public func sendPhoto(_ jpeg: Data) async {
        let localID = "local-\(UUID().uuidString)"
        unsent[localID] = .photo(jpeg)
        var item = Item(
            message: placeholder(localID, content: .unsupported(.image)), delivery: .sending)
        item.localPhoto = jpeg
        items.append(item)
        await deliver(localID)
    }

    public func retry(_ item: Item) async {
        guard item.delivery == .failed, let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        items[index].delivery = .sending
        await deliver(item.id)
    }

    /// Drops a message that failed to send.
    public func discard(_ item: Item) {
        guard item.delivery == .failed else { return }
        items.removeAll { $0.id == item.id }
        unsent[item.id] = nil
    }

    private func deliver(_ localID: String) async {
        do {
            let message: OutgoingMessage
            switch unsent[localID] {
            case .message(let pending):
                message = pending
            case .photo(let jpeg):
                message = .image(mediaID: try await api.uploadChatPhoto(jpeg).mediaID)
                // A retry after a failed send doesn't upload the photo again.
                unsent[localID] = .message(message)
            case nil:
                return
            }
            let sent = try await api.send(message, to: otherProfileID)
            unsent[localID] = nil
            items.removeAll { $0.id == localID }
            // The websocket may have delivered the echo first.
            if !items.contains(where: { $0.id == sent.id }) {
                insert(sent)
            }
            session?.inbox.noteSent(sent)
        } catch {
            if let index = items.firstIndex(where: { $0.id == localID }) {
                items[index].delivery = .failed
            }
            actionFailure = Failure(error)
        }
    }

    private enum Unsent {
        case message(OutgoingMessage)
        /// Not uploaded yet.
        case photo(Data)
    }

    private func placeholder(_ id: String, content: Message.Content) -> Message {
        Message(id: id, conversationID: conversationID, senderID: me, date: .now, content: content)
    }

    private static func optimisticContent(_ message: OutgoingMessage) -> Message.Content {
        switch message {
        case .text(let text): .text(text)
        case .image: .unsupported(.image)
        }
    }

    // MARK: Message actions

    /// Unsends one of your messages for both sides.
    public func unsend(_ item: Item) async {
        guard isOutgoing(item), item.delivery == .sent,
            let index = items.firstIndex(where: { $0.id == item.id })
        else { return }
        let original = items[index]
        items[index].message.content = .unsent
        do {
            try await api.unsend(item.id, in: conversationID)
        } catch {
            restore(original)
            actionFailure = Failure(error)
        }
    }

    /// Deletes a message from your side of the conversation.
    public func deleteForMe(_ item: Item) async {
        guard item.delivery == .sent, let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        let removed = items.remove(at: index)
        do {
            try await api.deleteMessage(item.id, in: conversationID)
        } catch {
            items.insert(removed, at: min(index, items.count))
            actionFailure = Failure(error)
        }
    }

    public func hasHeart(_ item: Item) -> Bool {
        item.message.reactions.contains { $0.profileID == me }
    }

    /// Hearts a message. Grindr has no way to take a reaction back.
    public func heart(_ item: Item) async {
        guard item.delivery == .sent, !hasHeart(item),
            let index = items.firstIndex(where: { $0.id == item.id })
        else { return }
        let original = items[index]
        items[index].message.reactions.append(
            MessageReaction(profileID: me, type: MessageReaction.heart))
        do {
            try await api.react(to: item.id, in: conversationID)
        } catch {
            restore(original)
            actionFailure = Failure(error)
        }
    }

    private func restore(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    // MARK: Live updates

    func handle(_ event: RealtimeEvent) {
        switch event {
        case .message(let message) where message.conversationID == conversationID:
            if let target = message.retractedMessageID {
                if let index = items.firstIndex(where: { $0.id == target }) {
                    items[index].message.content = .unsent
                }
                return
            }
            if message.senderID == otherProfileID {
                setTyping(false)
            }
            insert(message)
            markReadIfNeeded()
        case .conversationRead(let id, let reader, let date)
        where id == conversationID && reader == otherProfileID:
            readByOtherUntil = max(readByOtherUntil ?? date, date)
        case .typing(let id, let profileID, let isTyping)
        where id == conversationID && profileID == otherProfileID:
            setTyping(isTyping)
        case .conversationsDeleted(let ids) where ids.contains(conversationID):
            items.removeAll()
            olderPageKey = nil
        default:
            break
        }
    }

    /// Adds a message in date order, or replaces the copy already shown (the
    /// server re-sends a message when it gets a reaction).
    private func insert(_ message: Message) {
        if let index = items.firstIndex(where: { $0.id == message.id }) {
            items[index].message = message
            return
        }
        let item = Item(message: message, delivery: .sent)
        // Messages still being sent stay at the bottom.
        let sentEnd = items.lastIndex { $0.delivery == .sent }.map { $0 + 1 } ?? 0
        let index = items[..<sentEnd].lastIndex { $0.message.date <= message.date }.map { $0 + 1 } ?? 0
        items.insert(item, at: index)
    }

    private func setTyping(_ isTyping: Bool) {
        typingReset?.cancel()
        isOtherTyping = isTyping
        guard isTyping else { return }
        // The server does not always send "Cleared"; stop showing it after a while.
        typingReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.isOtherTyping = false
        }
    }

    private func markReadIfNeeded() {
        guard isVisible,
            let latest = items.last(where: {
                $0.delivery == .sent && $0.message.senderID == otherProfileID
            }),
            latest.id != lastMarkedRead
        else { return }
        lastMarkedRead = latest.id
        session?.inbox.markRead(conversationID)
        let api = api
        let conversationID = conversationID
        Task {
            try? await api.markRead(conversationID, through: latest.id)
        }
    }

    /// Hides protocol messages that only change other messages.
    private static func visible(_ messages: some Sequence<Message>) -> [Message] {
        messages.filter { $0.content.kind != .retract }
    }
}
