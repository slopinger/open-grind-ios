import Foundation

/// A realtime event from Grindr's websocket, decoded into what the app reacts to.
public enum RealtimeEvent: Sendable, Hashable {
    /// A message was sent or received, or a message changed (reaction, unsend).
    case message(Message)
    /// `profileID` read the conversation up to and including `date`.
    case conversationRead(conversationID: String, profileID: ProfileID, date: Date)
    /// Conversations were deleted, for example because someone blocked you.
    case conversationsDeleted([String])
    /// Conversations changed and should be fetched again.
    case conversationsChanged([String])
    case typing(conversationID: String, profileID: ProfileID, isTyping: Bool)
    case tapReceived(Tap)
    case profileViewed(by: ProfileID, photoHash: String?, totalViews: Int?)
    /// The inbox should be fetched again.
    case inboxInvalidated
    /// A reply to a command sent with `refID`.
    case commandResponse(type: String, refID: String, status: Int?, payload: Data)
    /// An event this version does not handle.
    case other(type: String)

    /// Decodes an event from its `type` and the whole event's JSON.
    public static func decode(type: String, json: Data) -> RealtimeEvent {
        decodeKnown(type: type, json: json) ?? .other(type: type)
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        var payload: Payload
    }

    private static func decodeKnown(type: String, json: Data) -> RealtimeEvent? {
        func payload<T: Decodable>(_ type: T.Type) -> T? {
            try? JSON.decode(Envelope<T>.self, from: json).payload
        }
        switch type {
        case "chat.v1.message_sent":
            return payload(Message.self).map(RealtimeEvent.message)
        case "chat.v1.conversation_read":
            return payload(ReadPayload.self).map {
                .conversationRead(conversationID: $0.conversationId, profileID: $0.profileID, date: $0.date)
            }
        case "chat.v1.conversation.delete":
            return payload(ConversationIDs.self).map { .conversationsDeleted($0.conversationIds) }
        case "chat.v1.conversation.update":
            return payload(ConversationIDs.self).map { .conversationsChanged($0.conversationIds) }
        case "chat.v1.refresh_dynamic":
            return payload(SingleConversation.self).map { .conversationsChanged([$0.conversationId]) }
        case "chat.v1.typing_status":
            return payload(TypingPayload.self).map {
                .typing(
                    conversationID: $0.conversationId, profileID: $0.profileID,
                    isTyping: $0.status == "Typing")
            }
        case "tap.v1.tap_sent", "tap.v2.tap_sent":
            return payload(TapPayload.self).map { .tapReceived($0.tap) }
        case "viewed_me.v1.new_view_received":
            return payload(ViewPayload.self).flatMap { view in
                view.mostRecent.map {
                    .profileViewed(by: $0.profileID, photoHash: $0.photoHash, totalViews: view.viewedCount)
                }
            }
        case "chat.v1.cache_bomb.inbox":
            return .inboxInvalidated
        default:
            guard type.hasSuffix(".response"), let reply = try? JSON.decode(Reply.self, from: json) else {
                return nil
            }
            return .commandResponse(
                type: String(type.dropLast(".response".count)), refID: reply.ref ?? "",
                status: reply.status,
                payload: json)
        }
    }

    private struct ConversationIDs: Decodable {
        var conversationIds: [String]
    }

    private struct SingleConversation: Decodable {
        var conversationId: String
    }

    private struct ReadPayload: Decodable {
        var conversationId: String
        var profileID: ProfileID
        var date: Date

        enum CodingKeys: String, CodingKey {
            case conversationId, profileId, timestamp
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            conversationId = try container.decode(String.self, forKey: .conversationId)
            profileID = try container.decodeFlexibleInt(forKey: .profileId)
            date = container.timestamp(forKey: .timestamp) ?? .now
        }
    }

    private struct TypingPayload: Decodable {
        var conversationId: String
        var profileID: ProfileID
        var status: String

        enum CodingKeys: String, CodingKey {
            case conversationId, profileId, status
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            conversationId = try container.decode(String.self, forKey: .conversationId)
            profileID = try container.decodeFlexibleInt(forKey: .profileId)
            status = try container.decode(String.self, forKey: .status)
        }
    }

    private struct TapPayload: Decodable {
        var tap: Tap

        enum CodingKeys: String, CodingKey {
            case senderId, senderDisplayName, senderProfileImageHash, timestamp, tapType, isMutual
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tap = Tap(
                profileID: try container.decodeFlexibleInt(forKey: .senderId),
                displayName: container.lenient(String.self, forKey: .senderDisplayName),
                photoHash: container.lenient(String.self, forKey: .senderProfileImageHash),
                date: container.timestamp(forKey: .timestamp) ?? .now,
                type: TapType.known(container.lenient(Int.self, forKey: .tapType)),
                isMutual: container.flag(forKey: .isMutual))
        }
    }

    private struct ViewPayload: Decodable {
        struct Viewer: Decodable {
            var profileID: ProfileID
            var photoHash: String?

            enum CodingKeys: String, CodingKey {
                case profileId, photoHash
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                profileID = try container.decodeFlexibleInt(forKey: .profileId)
                photoHash = container.lenient(String.self, forKey: .photoHash)
            }
        }

        var viewedCount: Int?
        var mostRecent: Viewer?
    }

    private struct Reply: Decodable {
        var ref: String?
        var status: Int?
    }
}
