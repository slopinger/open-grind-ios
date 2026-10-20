import Foundation

/// A transport that answers from local sample data instead of Grindr, so the
/// app can be tried (and reviewed) without an account.
///
/// Responses are encoded in the API's own JSON shapes and decoded by the same
/// code as real responses. Photos are illustrations from DiceBear, loaded by
/// `loadImage` (the app passes a `URLSession` fetch); without it, photos fail
/// to load and the app shows placeholders.
public final class DemoTransport: GrindrTransport, @unchecked Sendable {
    public typealias ImageLoader = @Sendable (URL) async throws -> Data

    /// The demo account's profile id.
    public static let profileID = DemoWorld.myProfileID
    /// The demo account's location (Berlin).
    public static let geohash = DemoWorld.geohash
    /// Credentials that resume the demo account.
    public static let credentials = #"{"profile_id":"\#(DemoWorld.myProfileID)","demo":true}"#

    private let world: DemoWorld
    private let loadImage: ImageLoader?
    private let replyDelay: Duration
    private let lock = NSLock()
    private var handler: (@Sendable (TransportEvent) -> Void)?

    public init(now: Date = .now, replyDelay: Duration = .seconds(2), loadImage: ImageLoader? = nil) {
        world = DemoWorld(now: now)
        self.loadImage = loadImage
        self.replyDelay = replyDelay
    }

    public func setEventHandler(_ handler: @escaping @Sendable (TransportEvent) -> Void) {
        lock.withLock { self.handler = handler }
    }

    private func emit(_ event: TransportEvent) {
        let handler = lock.withLock { self.handler }
        handler?(event)
    }

    public func signIn(email: String, password: String, geohash: String?) async throws -> SignInResult {
        emit(.credentialsChanged(Self.credentials))
        return SignInResult(profileID: Self.profileID)
    }

    public func signOut() async throws {
        emit(.credentialsChanged(nil))
    }

    public func connectRealtime() async throws {
        emit(.realtimeConnectionChanged(isConnected: true))
    }

    public func sendRealtimeCommand(type: String, refID: String, payload: Data) async throws {}

    public func setActive(_ isActive: Bool) {}

    public func fetchMedia(at url: URL, maxBytes: Int) async throws -> MediaPayload {
        let hash = url.lastPathComponent
        if let uploaded = await world.uploadedPhoto(hash) {
            return MediaPayload(status: 200, contentType: "image/jpeg", data: uploaded)
        }
        guard let seed = await world.photoSeed(for: hash), let loadImage else {
            return MediaPayload(status: 404, data: Data())
        }
        let size = url.path.contains("thumb") ? 320 : 1024
        let colors = ["b6e3f4", "c0aede", "d1d4f9", "ffd5dc", "ffdfbf", "c7f0d8"]
        let color = colors[seed.utf8.reduce(0) { $0 &+ Int($1) } % colors.count]
        let avatar = URL(
            string:
                "https://api.dicebear.com/9.x/notionists/png?seed=\(seed)&size=\(size)&backgroundColor=\(color)"
        )!
        return MediaPayload(status: 200, contentType: "image/png", data: try await loadImage(avatar))
    }

    // MARK: REST

    public func send(_ request: APIRequest) async throws -> APIResponse {
        // A little latency, so loading states are visible as they would be.
        try await Task.sleep(for: .milliseconds(250))
        let (path, query) = Self.split(request.path)
        let parts = path.split(separator: "/").map(String.init)
        let body: Data = if case .json(let data) = request.body { data } else { Data() }

        let route = Route(method: request.method, segments: parts)

        if route.matches(.get, "v4/cascade") {
            return try await cascade(query)
        }
        if route.matches(.put, "v4/location") || route.matches(.post, "v5/views/*")
            || route.matches(.post, "v4/flags/*")
        {
            return .ok
        }
        if let id = route.id(.get, "v7/profiles/*") {
            guard let profile = await world.profile(id) else { return .notFound }
            return try .json(["profiles": .array([Self.encode(profile)])])
        }
        if route.matches(.post, "v3/profiles") {
            let ids = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?[
                "targetProfileIds"]
            var summaries: [JSONValue] = []
            for id in DemoWorld.ints(ids) ?? [] {
                if let profile = await world.summary(id) { summaries.append(Self.encodeSummary(profile)) }
            }
            return try .json(["profiles": .array(summaries)])
        }
        if route.matches(.post, "v4/media/upload") {
            guard case .bytes(_, let data) = request.body else { return .badRequest }
            let upload = await world.upload(data)
            return try .json([
                "hash": .string(upload.hash), "mediaId": .int(upload.mediaID),
                "imageSizes": .array([
                    .object([
                        "mediaHash": .string(upload.hash), "fullUrl": .string(upload.url.absoluteString),
                        "state": .string("Pending"),
                    ])
                ]),
            ])
        }
        if route.matches(.put, "v3/me/profile/images") {
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let primary = object?["primaryImageHash"] as? String
            let secondary = object?["secondaryImageHashes"] as? [String] ?? []
            await world.setMyPhotos((primary.map { [$0] } ?? []) + secondary)
            return .ok
        }
        if route.matches(.delete, "v3/me/profile/images") {
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            await world.deleteMyPhotos(Set(object?["media_hashes"] as? [String] ?? []))
            return .ok
        }
        if route.matches(.patch, "v4/me/profile") {
            await world.updateMe(body)
            return .ok
        }
        if let id = route.id(.post, "v3/me/favorites/*") ?? route.id(.delete, "v3/me/favorites/*") {
            await world.setFavorite(id, request.method == .post)
            return .ok
        }
        if route.matches(.get, "public/v2/genders") {
            return try .json(
                .array(
                    [
                        (1, "Man", "Men"), (2, "Woman", "Women"), (3, "Non-binary", "Non-binary people"),
                        (4, "Trans Man", "Trans men"), (5, "Trans Woman", "Trans women"),
                    ].map { id, name, plural in
                        .object([
                            "genderId": .int(id), "gender": .string(name), "genderPlural": .string(plural),
                            "displayGroup": .int(1),
                        ])
                    }))
        }
        if route.matches(.get, "v1/tags") {
            let categories = DemoWorld.tagCatalog.categories.map { category -> JSONValue in
                .object([
                    "text": .string(category.name), "possessiveText": .null,
                    "tags": .array(
                        category.tags.enumerated().map { index, tag in
                            .object(["tagId": .int(index), "key": .string(tag.key), "text": .string(tag.text)])
                        }),
                ])
            }
            return try .json(.array([.object(["language": .string("en"), "categoryCollection": .array(categories)])]))
        }
        if route.matches(.get, "v1/pronouns") {
            return try .json(
                .array(
                    [(1, "He/Him"), (2, "She/Her"), (3, "They/Them")].map {
                        .object(["pronounId": .int($0.0), "pronoun": .string($0.1)])
                    }))
        }
        if let id = route.id(.post, "v3/me/blocks/*") {
            await world.block(id)
            return .ok
        }
        if let id = route.id(.delete, "v3/me/blocks/*") {
            await world.unblock(id)
            return .ok
        }
        if route.matches(.get, "v3.1/me/blocks") {
            let blocked = await world.blockedProfiles()
            return try .json([
                "blocking": .array(
                    blocked.map {
                        .object([
                            "profileId": .int($0.id),
                            "blockedTime": .number(Double($0.blockedAt?.milliseconds ?? 0)),
                        ])
                    })
            ])
        }
        if let id = route.id(.post, "v1/me/hides/*") {
            await world.hide(id)
            return .ok
        }
        if route.matches(.post, "v2/taps/add") {
            return try .json(["isMutual": .bool(false)])
        }
        if route.matches(.get, "v2/taps/received") {
            return try .json(["profiles": .array(await world.receivedTaps().map(Self.encode))])
        }
        if route.matches(.get, "v7/views/list") {
            let viewers = await world.profileViewers()
            return try .json([
                "profiles": .array(viewers.map(Self.encode)),
                "previews": .array(Array(repeating: .object([:]), count: 4)),
            ])
        }
        if route.matches(.post, "v4/inbox") {
            return try await inbox(query, filter: body)
        }
        if let id = route.capture(.get, "v5/chat/conversation/*/message")?.first {
            return try await messages(id, pageKey: query["pageKey"])
        }
        if route.matches(.post, "v4/chat/message/send") {
            guard let message = await world.send(body) else { return .badRequest }
            scheduleReply(in: message.conversationID)
            return try .json(Self.encode(message), status: 201)
        }
        if route.matches(.post, "v5/chat/media/upload") {
            guard case .bytes(_, let data) = request.body else { return .badRequest }
            let upload = await world.upload(data)
            return try .json([
                "mediaId": .int(upload.mediaID), "url": .string(upload.url.absoluteString),
                "mediaHash": .string(upload.hash),
            ])
        }
        if let id = route.capture(.post, "v4/chat/conversation/*/read/*")?.first {
            await world.markRead(id)
            return .ok
        }
        if let captured = route.capture(.post, "v4/chat/conversation/*/*"),
            captured[1] == "pin" || captured[1] == "unpin"
        {
            await world.setPinned(captured[0], captured[1] == "pin")
            return .ok
        }
        if let captured = route.capture(.post, "v1/push/conversation/*/*") {
            await world.setMuted(captured[0], captured[1] == "mute")
            return .ok
        }
        if let id = route.capture(.delete, "v4/chat/conversation/*")?.first {
            await world.deleteConversation(id)
            return .ok
        }
        if let action = route.capture(.post, "v4/chat/message/*")?.first {
            let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            guard let conversationID = fields?["conversationId"] as? String,
                let messageID = fields?["messageId"] as? String
            else { return .badRequest }
            switch action {
            case "unsend": await world.unsend(messageID, in: conversationID)
            case "delete": await world.deleteMessage(messageID, in: conversationID)
            case "reaction":
                if let message = await world.react(to: messageID, in: conversationID) {
                    emitRealtime("chat.v1.message_sent", Self.encode(message))
                }
            default: return .notFound
            }
            return .ok
        }
        return .notFound
    }

    /// A request's method and path segments, matched against patterns where
    /// `*` stands for one segment.
    private struct Route {
        var method: HTTPMethod
        var segments: [String]

        func capture(_ method: HTTPMethod, _ pattern: String) -> [String]? {
            let pattern = pattern.split(separator: "/").map(String.init)
            guard method == self.method, pattern.count == segments.count else { return nil }
            var captured: [String] = []
            for (expected, actual) in zip(pattern, segments) {
                if expected == "*" {
                    captured.append(actual)
                } else if expected != actual {
                    return nil
                }
            }
            return captured
        }

        func matches(_ method: HTTPMethod, _ pattern: String) -> Bool {
            capture(method, pattern) != nil
        }

        func id(_ method: HTTPMethod, _ pattern: String) -> ProfileID? {
            capture(method, pattern)?.first.flatMap { Int($0) }
        }
    }

    private func cascade(_ query: [String: String]) async throws -> APIResponse {
        var filters = BrowseFilters()
        filters.onlineOnly = query["onlineOnly"] == "true"
        filters.photosOnly = query["photoOnly"] == "true"
        filters.facePhotosOnly = query["faceOnly"] == "true"
        filters.favoritesOnly = query["favorites"] == "true"
        if let min = query["ageMin"].flatMap(Int.init), let max = query["ageMax"].flatMap(Int.init),
            min <= max
        {
            filters.ages = min...max
        }
        func ids<T: ProfileAttribute>(_ key: String) -> Set<T> {
            Set(
                (query[key] ?? "").split(separator: ",").compactMap { Int($0).flatMap(T.init(rawValue:)) })
        }
        filters.positions = ids("sexualPositions")
        filters.lookingFor = ids("lookingFor")
        filters.tribes = ids("tribes")
        filters.tags = Set((query["tags"] ?? "").split(separator: ",").map(String.init))
        let page = await world.gridPage(
            filters: filters, exploring: query["exploreGeoHash"], page: query["pageNumber"].flatMap(Int.init) ?? 1)
        var items = page.profiles.map { profile -> JSONValue in
            .object(["type": .string("full_profile_v1"), "data": Self.encodeGridData(profile)])
        }
        // Real pages mix in ads and upsells, which the client must skip.
        if !items.isEmpty {
            items.insert(
                .object(["type": .string("advert_v1"), "data": .object([:])]), at: min(6, items.count))
        }
        return try .json([
            "items": .array(items), "nextPage": .optional(page.nextPage), "shuffled": .bool(false),
        ])
    }

    private func inbox(_ query: [String: String], filter: Data) async throws -> APIResponse {
        let options = (try? JSONSerialization.jsonObject(with: filter)) as? [String: Any] ?? [:]
        let unreadOnly = DemoWorld.bool(options["unreadOnly"]) ?? false
        let favoritesOnly = DemoWorld.bool(options["favoritesOnly"]) ?? false
        let onlineOnly = DemoWorld.bool(options["onlineNowOnly"]) ?? false
        guard (query["page"].flatMap(Int.init) ?? 1) == 1 else {
            return try .json(["entries": .array([]), "nextPage": .null])
        }
        let entries = await world.conversations().filter { entry in
            (!unreadOnly || entry.thread.unread > 0) && (!favoritesOnly || entry.profile.isFavorite)
                && (!onlineOnly || entry.profile.isOnline())
        }
        return try .json([
            "entries": .array(
                entries.map { id, thread, profile in
                    let last = thread.messages.last
                    return .object([
                        "type": .string("full_conversation_v1"),
                        "data": .object([
                            "conversationId": .string(id),
                            "name": .optional(profile.displayName),
                            "participants": .array([
                                .object([
                                    "profileId": .int(profile.id),
                                    "primaryMediaHash": .optional(profile.primaryPhoto?.mediaHash),
                                    "onlineUntil": .optional(profile.onlineUntil.map { Double($0.milliseconds) }),
                                    "distanceMetres": .optional(profile.distance),
                                    "position": .optional(profile.position?.rawValue),
                                ])
                            ]),
                            "lastActivityTimestamp": .number(Double(last?.date.milliseconds ?? 0)),
                            "unreadCount": .int(thread.unread),
                            "preview": last.map {
                                .object([
                                    "messageId": .string($0.id), "type": .string($0.content.kind.rawValue),
                                    "text": .optional($0.previewText), "senderId": .int($0.senderID),
                                    "unsent": .bool($0.content == .unsent),
                                ])
                            } ?? .null,
                            "muted": .bool(thread.isMuted),
                            "pinned": .bool(thread.isPinned),
                            "favorite": .bool(profile.isFavorite),
                        ]),
                    ])
                }),
            "nextPage": .null,
        ])
    }

    private func messages(_ conversationID: String, pageKey: String?) async throws -> APIResponse {
        guard let thread = await world.thread(conversationID),
            let profile = await world.profile(thread.otherID)
        else {
            return APIResponse(
                status: 403, body: Data(#"{"type":"urn:gr:err:unauthorized_action"}"#.utf8))
        }
        let newestFirst = Array(thread.messages.reversed())
        let start =
            pageKey.flatMap { key in newestFirst.firstIndex { $0.id == key }.map { $0 + 1 } } ?? 0
        let page = newestFirst.dropFirst(start).prefix(30)
        return try .json([
            "lastReadTimestamp": .number(Double(Date.now.addingTimeInterval(-120).milliseconds)),
            "messages": .array(page.map(Self.encode)),
            "profile": .object([
                "profileId": .int(profile.id), "name": .optional(profile.displayName),
                "mediaHash": .optional(profile.primaryPhoto?.mediaHash),
                "onlineUntil": .optional(profile.onlineUntil.map { Double($0.milliseconds) }),
                "distance": .optional(profile.distance), "showDistance": .bool(profile.showsDistance),
            ]),
        ])
    }

    /// The other profile "types" and answers, like a person would.
    private func scheduleReply(in conversationID: String) {
        let delay = replyDelay
        Task { [weak self] in
            guard let self, let otherID = await world.thread(conversationID)?.otherID else { return }
            try? await Task.sleep(for: delay / 2)
            emitRealtime(
                "chat.v1.typing_status",
                .object([
                    "conversationId": .string(conversationID), "profileId": .int(otherID),
                    "status": .string("Typing"),
                ]))
            try? await Task.sleep(for: delay)
            guard let reply = await world.reply(in: conversationID) else { return }
            emitRealtime("chat.v1.message_sent", Self.encode(reply))
        }
    }

    private func emitRealtime(_ type: String, _ payload: JSONValue) {
        let event = JSONValue.object([
            "type": .string(type), "payload": payload, "notificationId": .null,
        ])
        guard let json = try? JSON.encode(event) else { return }
        emit(.realtime(type: type, json: json))
    }

    private static func split(_ path: String) -> (String, [String: String]) {
        let components = URLComponents(string: path)
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, last in last })
        return (components?.path ?? path, query)
    }

    // MARK: Encoding in API shapes

    private static func timestamp(_ date: Date?) -> JSONValue {
        date.map { .number(Double($0.milliseconds)) } ?? .null
    }

    private static func ids(_ values: [some ProfileAttribute]) -> JSONValue {
        .ints(values.map(\.rawValue))
    }

    static func encode(_ profile: Profile) -> JSONValue {
        .object([
            "profileId": .string(String(profile.id)),
            "displayName": .optional(profile.displayName),
            "aboutMe": .optional(profile.aboutMe),
            "age": .optional(profile.age),
            "showAge": .bool(profile.showsAge),
            "distance": .optional(profile.distance),
            "approximateDistance": .bool(profile.isDistanceApproximate),
            "showDistance": .bool(profile.showsDistance),
            "onlineUntil": timestamp(profile.onlineUntil),
            "seen": timestamp(profile.lastSeen),
            "medias": .array(
                profile.photos.map {
                    .object([
                        "mediaHash": .string($0.mediaHash), "type": .int(1), "state": .int($0.isPendingReview ? 0 : 1),
                        "reason": .null,
                    ])
                }),
            "profileImageMediaHash": .optional(profile.primaryPhoto?.mediaHash),
            "height": .optional(profile.height),
            "weight": .optional(profile.weight),
            "sexualPosition": .optional(profile.position?.rawValue),
            "bodyType": .optional(profile.bodyType?.rawValue),
            "ethnicity": .optional(profile.ethnicity?.rawValue),
            "relationshipStatus": .optional(profile.relationshipStatus?.rawValue),
            "grindrTribes": ids(profile.tribes),
            "lookingFor": ids(profile.lookingFor),
            "meetAt": ids(profile.meetAt),
            "nsfw": .optional(profile.acceptsNSFWPics?.rawValue),
            "hivStatus": .optional(profile.hivStatus?.rawValue),
            "lastTestedDate": timestamp(profile.lastTested),
            "sexualHealth": ids(profile.sexualHealth),
            "vaccines": ids(profile.vaccines),
            "genders": .ints(profile.genderIDs),
            "pronouns": .ints(profile.pronounIDs),
            "profileTags": .array(profile.tags.map(JSONValue.string)),
            "socialNetworks": profile.instagram.map {
                .object(["instagram": .object(["userId": .string($0)])])
            }
                ?? .object([:]),
            "isFavorite": .bool(profile.isFavorite),
            "tapType": .int(profile.receivedTap?.rawValue ?? 3),
            "tapped": .bool(profile.hasBeenTapped),
            "isNew": .bool(profile.isNew),
            "isVisiting": .bool(profile.isVisiting),
            "unreadCount": .int(profile.unreadCount),
            "showTribes": .bool(profile.showsTribes),
            "showPosition": .bool(profile.showsPosition),
        ])
    }

    static func encodeSummary(_ profile: Profile) -> JSONValue {
        .object([
            "profileId": .string(String(profile.id)), "displayName": .optional(profile.displayName),
            "age": .optional(profile.age), "distance": .optional(profile.distance),
            "onlineUntil": timestamp(profile.onlineUntil),
            "profileImageMediaHash": .optional(profile.primaryPhoto?.mediaHash),
            "isFavorite": .bool(profile.isFavorite),
        ])
    }

    static func encodeGridData(_ profile: Profile) -> JSONValue {
        .object([
            "profileId": .int(profile.id),
            "displayName": .optional(profile.displayName),
            "age": profile.showsAge ? .optional(profile.age) : .null,
            "distanceMeters": profile.showsDistance ? .optional(profile.distance) : .null,
            "primaryImageUrl": .optional(
                profile.primaryPhoto.map {
                    MediaURL.profileImage($0.mediaHash, size: .thumbnail).absoluteString
                }),
            "onlineUntil": timestamp(profile.onlineUntil),
            "lastOnline": timestamp(profile.lastSeen),
            "sexualPosition": .optional(profile.position?.rawValue),
            "unreadCount": .int(profile.unreadCount),
            "favorite": .bool(profile.isFavorite),
            "isVisiting": .bool(profile.isVisiting),
            "isPopular": .bool(profile.isNew),
        ])
    }

    static func encode(_ message: Message) -> JSONValue {
        let (type, body): (String, JSONValue) =
            switch message.content {
            case .text(let text): ("Text", .object(["text": .string(text)]))
            case .image(let url, let width, let height):
                (
                    "Image",
                    .object([
                        "mediaId": .int(1), "url": .string(url.absoluteString), "width": .optional(width),
                        "height": .optional(height), "imageHash": .string(url.lastPathComponent),
                        "takenOnGrindr": .bool(false), "createdAt": .null,
                    ])
                )
            case .location(let latitude, let longitude):
                ("Location", .object(["lat": .number(latitude), "lon": .number(longitude)]))
            case .unsent: ("Text", .null)
            default: ("Unknown", .null)
            }
        return .object([
            "messageId": .string(message.id),
            "conversationId": .string(message.conversationID),
            "senderId": .int(message.senderID),
            "timestamp": timestamp(message.date),
            "unsent": .bool(message.content == .unsent),
            "reactions": .array(
                message.reactions.map {
                    .object(["profileId": .int($0.profileID), "reactionType": .int($0.type)])
                }),
            "type": .string(type),
            "body": body,
            "dynamic": .bool(false),
        ])
    }

    static func encode(_ tap: Tap) -> JSONValue {
        .object([
            "profileId": .string(String(tap.profileID)), "displayName": .optional(tap.displayName),
            "profileImageMediaHash": .optional(tap.photoHash), "distance": .optional(tap.distance),
            "timestamp": timestamp(tap.date), "tapType": .int(tap.type?.rawValue ?? 3),
            "isMutual": .bool(tap.isMutual),
            "onlineUntil": timestamp(tap.onlineUntil), "isFavorite": .bool(tap.isFavorite),
            "isViewable": .bool(true),
            "isBoosting": .bool(false), "rightNowType": .string("NONE"), "lastOnline": .null,
        ])
    }

    static func encode(_ viewer: ProfileViewer) -> JSONValue {
        .object([
            "profileId": .string(String(viewer.profileID)), "displayName": .optional(viewer.displayName),
            "profileImageMediaHash": .optional(viewer.photoHash), "distance": .optional(viewer.distance),
            "lastViewed": timestamp(viewer.lastViewed), "onlineUntil": timestamp(viewer.onlineUntil),
            "isFavorite": .bool(viewer.isFavorite), "isSecretAdmirer": .bool(false),
            "viewedCount": .object(["totalCount": .int(viewer.viewCount), "maxDisplayCount": .int(99)]),
        ])
    }
}

extension APIResponse {
    fileprivate static let ok = APIResponse(status: 200, body: Data("{}".utf8))
    fileprivate static let notFound = APIResponse(
        status: 404, body: Data(#"{"code":404,"message":"Not found"}"#.utf8))
    fileprivate static let badRequest = APIResponse(status: 400, body: Data(#"{"code":400}"#.utf8))

    fileprivate static func json(_ value: JSONValue, status: Int = 200) throws -> APIResponse {
        APIResponse(status: status, body: try JSON.encode(value))
    }

    fileprivate static func json(_ object: [String: JSONValue], status: Int = 200) throws
        -> APIResponse
    {
        try json(.object(object), status: status)
    }
}
