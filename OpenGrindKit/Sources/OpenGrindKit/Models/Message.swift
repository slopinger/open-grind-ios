import Foundation

/// A message type as the API names it (`Text`, `Image`, ...). Open-ended:
/// Grindr adds types, and unknown ones must still round-trip.
public struct MessageKind: RawRepresentable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let text = MessageKind(rawValue: "Text")
    public static let image = MessageKind(rawValue: "Image")
    public static let expiringImage = MessageKind(rawValue: "ExpiringImage")
    public static let location = MessageKind(rawValue: "Location")
    public static let gaymoji = MessageKind(rawValue: "Gaymoji")
    public static let giphy = MessageKind(rawValue: "Giphy")
    public static let audio = MessageKind(rawValue: "Audio")
    public static let video = MessageKind(rawValue: "Video")
    public static let privateVideo = MessageKind(rawValue: "PrivateVideo")
    public static let album = MessageKind(rawValue: "Album")
    public static let expiringAlbum = MessageKind(rawValue: "ExpiringAlbum")
    public static let expiringAlbumV2 = MessageKind(rawValue: "ExpiringAlbumV2")
    public static let profilePhotoReply = MessageKind(rawValue: "ProfilePhotoReply")
    public static let retract = MessageKind(rawValue: "Retract")
    public static let videoCall = MessageKind(rawValue: "VideoCall")
}

/// A reaction on a message.
public struct MessageReaction: Hashable, Sendable {
    public var profileID: ProfileID
    /// `1` is the heart the official app offers.
    public var type: Int

    public init(profileID: ProfileID, type: Int) {
        self.profileID = profileID
        self.type = type
    }

    public static let heart = 1
}

/// A chat message.
public struct Message: Identifiable, Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case text(String)
        case image(url: URL, width: Int?, height: Int?)
        /// A view-once photo; `url` is gone once it has been viewed or expired.
        case expiringImage(url: URL?)
        case location(latitude: Double, longitude: Double)
        case gaymoji(imageHash: String)
        case giphy(url: URL, width: Int, height: Int)
        /// A reply to one of your profile photos.
        case profilePhotoReply(imageHash: String, text: String)
        case audio(url: URL, duration: TimeInterval?)
        case video(url: URL?)
        case album(coverURL: URL?, isViewable: Bool)
        /// Unsent by its sender.
        case unsent
        /// A type this version does not show.
        case unsupported(MessageKind)
    }

    public var id: String
    public var conversationID: String
    public var senderID: ProfileID
    public var date: Date
    public var content: Content
    public var reactions: [MessageReaction]
    /// For a `Retract` message: the message it unsends.
    public var retractedMessageID: String?
    /// The message this one replies to, when the server includes it.
    public var replyToMessageID: String?

    public init(
        id: String, conversationID: String, senderID: ProfileID, date: Date, content: Content,
        reactions: [MessageReaction] = [], retractedMessageID: String? = nil,
        replyToMessageID: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.date = date
        self.content = content
        self.reactions = reactions
        self.retractedMessageID = retractedMessageID
        self.replyToMessageID = replyToMessageID
    }

    /// Text to put in a notification, preview or accessibility label.
    public var previewText: String? {
        if case .text(let text) = content { return text }
        if case .profilePhotoReply(_, let text) = content { return text }
        return nil
    }
}

extension Message: Decodable {
    enum CodingKeys: String, CodingKey {
        case messageId, conversationId, senderId, timestamp, unsent, reactions, type, body,
            replyToMessage
    }

    enum BodyKeys: String, CodingKey {
        case text, url, width, height, lat, lon, imageHash, urlPath, photoContentReply, length, coverUrl
        case isViewable, targetMessageId
    }

    private struct Reaction: Decodable {
        var profileId: Int
        var reactionType: Int
    }

    private struct ReplyReference: Decodable {
        var messageId: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .messageId)
        conversationID = try container.decode(String.self, forKey: .conversationId)
        senderID = try container.decodeFlexibleInt(forKey: .senderId)
        date = container.timestamp(forKey: .timestamp) ?? .now
        reactions = container.lossyArray(of: Reaction.self, forKey: .reactions).map {
            MessageReaction(profileID: $0.profileId, type: $0.reactionType)
        }
        replyToMessageID = container.lenient(ReplyReference.self, forKey: .replyToMessage)?.messageId
        retractedMessageID = nil

        let kind = MessageKind(rawValue: try container.decode(String.self, forKey: .type))
        if container.flag(forKey: .unsent) {
            content = .unsent
            return
        }
        guard let body = try? container.nestedContainer(keyedBy: BodyKeys.self, forKey: .body) else {
            content = .unsupported(kind)
            return
        }
        content = Self.content(of: kind, body: body) ?? .unsupported(kind)
        if kind == .retract {
            retractedMessageID = body.lenient(String.self, forKey: .targetMessageId)
        }
    }

    private static func content(of kind: MessageKind, body: KeyedDecodingContainer<BodyKeys>)
        -> Content?
    {
        func url(_ key: BodyKeys) -> URL? {
            body.lenient(String.self, forKey: key).flatMap(MediaURL.validated)
        }
        switch kind {
        case .text:
            return body.lenient(String.self, forKey: .text).map(Content.text)
        case .image:
            guard let url = url(.url) else { return nil }
            return .image(
                url: url, width: body.lenient(Int.self, forKey: .width),
                height: body.lenient(Int.self, forKey: .height))
        case .expiringImage:
            return .expiringImage(url: url(.url))
        case .location:
            guard let latitude = body.lenient(Double.self, forKey: .lat),
                let longitude = body.lenient(Double.self, forKey: .lon)
            else { return nil }
            return .location(latitude: latitude, longitude: longitude)
        case .gaymoji:
            return body.lenient(String.self, forKey: .imageHash).map { .gaymoji(imageHash: $0) }
        case .giphy:
            guard let url = url(.urlPath) else { return nil }
            return .giphy(
                url: url, width: body.lenient(Int.self, forKey: .width) ?? 200,
                height: body.lenient(Int.self, forKey: .height) ?? 200)
        case .profilePhotoReply:
            guard let hash = body.lenient(String.self, forKey: .imageHash),
                let text = body.lenient(String.self, forKey: .photoContentReply)
            else { return nil }
            return .profilePhotoReply(imageHash: hash, text: text)
        case .audio:
            guard let url = url(.url) else { return nil }
            return .audio(
                url: url, duration: body.lenient(Double.self, forKey: .length).map { $0 / 1000 })
        case .video, .privateVideo:
            return .video(url: url(.url))
        case .album, .expiringAlbum, .expiringAlbumV2:
            return .album(coverURL: url(.coverUrl), isViewable: body.flag(forKey: .isViewable))
        default:
            return nil
        }
    }
}

/// The profile shown at the top of a conversation.
public struct ConversationProfile: Hashable, Sendable, Decodable {
    public var id: ProfileID
    public var name: String?
    public var photoHash: String?
    public var onlineUntil: Date?
    public var distance: Double?

    enum CodingKeys: String, CodingKey {
        case profileId, name, mediaHash, onlineUntil, distance, showDistance
    }

    public init(
        id: ProfileID, name: String?, photoHash: String? = nil, onlineUntil: Date? = nil,
        distance: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.photoHash = photoHash
        self.onlineUntil = onlineUntil
        self.distance = distance
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleInt(forKey: .profileId)
        name = container.lenient(String.self, forKey: .name)
        photoHash = container.lenient(String.self, forKey: .mediaHash)
        onlineUntil = container.timestamp(forKey: .onlineUntil)
        let showsDistance = container.lenient(Bool.self, forKey: .showDistance) ?? true
        distance = showsDistance ? container.lenient(Double.self, forKey: .distance) : nil
    }
}

/// One page of a conversation, newest message first.
public struct MessagePage: Sendable, Hashable, Decodable {
    public var messages: [Message]
    /// Everything up to this time has been read by the other side.
    public var lastRead: Date?
    public var profile: ConversationProfile?
    /// Pass to the next request to get older messages; `nil` at the start.
    /// Pages are keyed by their oldest message, so an empty page is the end.
    public var nextPageKey: String? { messages.last?.id }

    enum CodingKeys: String, CodingKey {
        case messages, lastReadTimestamp, profile
    }

    public init(messages: [Message], lastRead: Date? = nil, profile: ConversationProfile? = nil) {
        self.messages = messages
        self.lastRead = lastRead
        self.profile = profile
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = container.lossyArray(of: Message.self, forKey: .messages)
        lastRead = container.timestamp(forKey: .lastReadTimestamp)
        profile = container.lenient(ConversationProfile.self, forKey: .profile)
    }
}

/// A message to send.
public enum OutgoingMessage: Hashable, Sendable {
    case text(String)
    /// A photo uploaded with ``GrindrAPI/uploadChatPhoto(_:)``.
    case image(mediaID: Int)
    case location(latitude: Double, longitude: Double)

    var kind: MessageKind {
        switch self {
        case .text: .text
        case .image: .image
        case .location: .location
        }
    }

    var body: JSONValue {
        switch self {
        case .text(let text): .object(["text": .string(text)])
        case .image(let mediaID): .object(["mediaId": .int(mediaID)])
        case .location(let latitude, let longitude):
            .object(["lat": .number(latitude), "lon": .number(longitude)])
        }
    }

    /// The `POST /v4/chat/message/send` body.
    func requestBody(to profileID: ProfileID) -> JSONValue {
        .object([
            "type": .string(kind.rawValue),
            "target": .object(["type": .string("Direct"), "targetId": .int(profileID)]),
            "body": body,
        ])
    }
}

/// A photo uploaded for chat.
public struct UploadedMedia: Hashable, Sendable, Decodable {
    public var mediaID: Int
    public var url: URL

    enum CodingKeys: String, CodingKey {
        case mediaId, url
    }

    public init(mediaID: Int, url: URL) {
        self.mediaID = mediaID
        self.url = url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = try container.decodeFlexibleInt(forKey: .mediaId)
        url = try container.decode(URL.self, forKey: .url)
    }
}
