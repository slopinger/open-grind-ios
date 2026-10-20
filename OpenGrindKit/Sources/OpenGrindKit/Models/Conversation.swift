import Foundation

/// The other side of a conversation.
public struct ConversationParticipant: Identifiable, Hashable, Sendable, OnlinePresence {
    public var id: ProfileID
    public var photoHash: String?
    public var onlineUntil: Date?
    public var lastOnline: Date?
    /// Meters.
    public var distance: Double?
    public var position: SexualPosition?

    public init(
        id: ProfileID, photoHash: String? = nil, onlineUntil: Date? = nil, lastOnline: Date? = nil,
        distance: Double? = nil, position: SexualPosition? = nil
    ) {
        self.id = id
        self.photoHash = photoHash
        self.onlineUntil = onlineUntil
        self.lastOnline = lastOnline
        self.distance = distance
        self.position = position
    }

}

/// What the inbox shows under a conversation's name.
public struct MessagePreview: Hashable, Sendable {
    public var messageID: String?
    public var kind: MessageKind
    public var text: String?
    public var senderID: ProfileID?
    public var isUnsent: Bool

    public init(
        messageID: String? = nil, kind: MessageKind, text: String? = nil, senderID: ProfileID? = nil,
        isUnsent: Bool = false
    ) {
        self.messageID = messageID
        self.kind = kind
        self.text = text
        self.senderID = senderID
        self.isUnsent = isUnsent
    }
}

/// An inbox entry.
public struct Conversation: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var participant: ConversationParticipant?
    public var lastActivity: Date
    public var unreadCount: Int
    public var preview: MessagePreview?
    public var isMuted: Bool
    public var isPinned: Bool
    public var isFavorite: Bool
    /// The server only shows a teaser of this conversation without a subscription.
    public var isLocked: Bool

    public init(
        id: String, name: String, participant: ConversationParticipant? = nil, lastActivity: Date,
        unreadCount: Int = 0, preview: MessagePreview? = nil, isMuted: Bool = false,
        isPinned: Bool = false,
        isFavorite: Bool = false, isLocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.participant = participant
        self.lastActivity = lastActivity
        self.unreadCount = unreadCount
        self.preview = preview
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.isLocked = isLocked
    }

    /// The id of the direct conversation between two profiles: both ids,
    /// smaller first, joined by a colon.
    public static func id(between first: ProfileID, and second: ProfileID) -> String {
        "\(min(first, second)):\(max(first, second))"
    }

    /// The profile you are talking to, from the conversation id.
    public func otherProfileID(me: ProfileID) -> ProfileID? {
        participant?.id ?? Self.otherProfileID(in: id, me: me)
    }

    /// The other profile in the direct conversation `conversationID`.
    public static func otherProfileID(in conversationID: String, me: ProfileID) -> ProfileID? {
        let ids = conversationID.split(separator: ":").compactMap { Int($0) }
        return ids.count == 2 ? ids.first { $0 != me } ?? ids[0] : nil
    }
}

extension Conversation: Decodable {
    enum CodingKeys: String, CodingKey {
        case type, data
    }

    enum DataKeys: String, CodingKey {
        case conversationId, name, participants, lastActivityTimestamp, unreadCount, preview, muted,
            pinned, favorite
    }

    private struct Participant: Decodable {
        var value: ConversationParticipant

        enum CodingKeys: String, CodingKey {
            case profileId, primaryMediaHash, onlineUntil, lastOnline, distanceMetres, position
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = ConversationParticipant(
                id: try container.decodeFlexibleInt(forKey: .profileId),
                photoHash: container.lenient(String.self, forKey: .primaryMediaHash),
                onlineUntil: container.timestamp(forKey: .onlineUntil),
                lastOnline: container.timestamp(forKey: .lastOnline),
                distance: container.lenient(Double.self, forKey: .distanceMetres),
                position: SexualPosition.known(container.lenient(Int.self, forKey: .position)))
        }
    }

    private struct Preview: Decodable {
        var value: MessagePreview

        enum CodingKeys: String, CodingKey {
            case messageId, type, text, senderId, unsent
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = MessagePreview(
                messageID: container.lenient(String.self, forKey: .messageId),
                kind: MessageKind(rawValue: container.lenient(String.self, forKey: .type) ?? ""),
                text: container.lenient(String.self, forKey: .text),
                senderID: container.flexibleInt(forKey: .senderId),
                isUnsent: container.flag(forKey: .unsent))
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "full_conversation_v1" || type == "partial_conversation_v1" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown inbox entry \(type)")
        }
        let data = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        id = try data.decode(String.self, forKey: .conversationId)
        name = data.lenient(String.self, forKey: .name) ?? ""
        participant = data.lossyArray(of: Participant.self, forKey: .participants).first?.value
        lastActivity = data.timestamp(forKey: .lastActivityTimestamp) ?? .distantPast
        unreadCount = data.lenient(Int.self, forKey: .unreadCount) ?? 0
        preview = data.lenient(Preview.self, forKey: .preview)?.value
        isMuted = data.flag(forKey: .muted)
        isPinned = data.flag(forKey: .pinned)
        isFavorite = data.flag(forKey: .favorite)
        isLocked = type == "partial_conversation_v1"
    }
}

/// One page of the inbox.
public struct InboxPage: Sendable, Hashable, Decodable {
    public var conversations: [Conversation]
    public var nextPage: Int?

    enum CodingKeys: String, CodingKey {
        case entries, nextPage
    }

    public init(conversations: [Conversation], nextPage: Int?) {
        self.conversations = conversations
        self.nextPage = nextPage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversations = container.lossyArray(of: Conversation.self, forKey: .entries)
        nextPage = container.lenient(Int.self, forKey: .nextPage)
    }
}

/// Inbox filters (`POST /v4/inbox`).
public struct InboxFilter: Hashable, Sendable, Codable {
    public var unreadOnly = false
    public var favoritesOnly = false
    public var onlineNowOnly = false

    public init(unreadOnly: Bool = false, favoritesOnly: Bool = false, onlineNowOnly: Bool = false) {
        self.unreadOnly = unreadOnly
        self.favoritesOnly = favoritesOnly
        self.onlineNowOnly = onlineNowOnly
    }

    public var isDefault: Bool { self == InboxFilter() }

    var requestBody: JSONValue {
        .object([
            "unreadOnly": .bool(unreadOnly),
            "chemistryOnly": .bool(false),
            "favoritesOnly": .bool(favoritesOnly),
            "rightNowOnly": .bool(false),
            "onlineNowOnly": .bool(onlineNowOnly),
            "distanceMeters": .null,
            "positions": .array([]),
        ])
    }
}
