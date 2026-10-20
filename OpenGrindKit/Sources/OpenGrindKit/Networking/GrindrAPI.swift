import Foundation

/// Typed access to the Grindr REST API, on top of a ``GrindrTransport``.
///
/// Endpoints and payloads follow Open Grind's API reference
/// (https://opengrind.org/grindr-api/).
public struct GrindrAPI: Sendable {
    public let transport: any GrindrTransport

    public init(transport: any GrindrTransport) {
        self.transport = transport
    }

    // MARK: Browse

    /// A page of profiles around `geohash`, your location, or around `exploring`
    /// when set. Exploring does not move your own profile.
    public func cascade(near geohash: String, exploring: String? = nil, filters: BrowseFilters, page: Int?)
        async throws -> CascadePage
    {
        var query = [URLQueryItem(name: "nearbyGeoHash", value: Geohash.coarsen(geohash))]
        if let exploring {
            query.append(URLQueryItem(name: "exploreGeoHash", value: Geohash.coarsen(exploring)))
        }
        query += filters.queryItems()
        if let page { query.append(URLQueryItem(name: "pageNumber", value: String(page))) }
        return try await decode(CascadePage.self, APIRequest(.get, "/v4/cascade", query: query))
    }

    /// Tells Grindr where you are, rounded to about 110 m.
    public func updateLocation(geohash: String) async throws {
        try await perform(
            .json(.put, "/v4/location", .object(["geohash": .string(Geohash.coarsen(geohash))])))
    }

    // MARK: Profiles

    public func profile(_ id: ProfileID) async throws -> Profile {
        struct Response: Decodable { var profiles: [Profile] }
        let response = try await decode(Response.self, APIRequest(.get, "/v7/profiles/\(id)"))
        guard let profile = response.profiles.first, !profile.isUnavailableStub else {
            throw GrindrError.unavailable
        }
        return profile
    }

    /// Short profiles for `ids`, fetched at once in batches the server accepts, in the order of `ids`.
    public func profiles(_ ids: [ProfileID]) async throws -> [ProfileSummary] {
        let batches = stride(from: 0, to: ids.count, by: 30).map { Array(ids[$0..<min($0 + 30, ids.count)]) }
        return try await withThrowingTaskGroup(of: (Int, [ProfileSummary]).self) { group in
            for (index, batch) in batches.enumerated() {
                group.addTask {
                    let request = try APIRequest.json(
                        .post, "/v3/profiles", .object(["targetProfileIds": .ints(batch)]))
                    return (index, try await decode(LossyProfiles<ProfileSummary>.self, request).profiles)
                }
            }
            var results = [[ProfileSummary]](repeating: [], count: batches.count)
            for try await (index, summaries) in group { results[index] = summaries }
            return results.flatMap { $0 }
        }
    }

    /// Saves the changed fields of your profile.
    public func updateProfile(_ patch: JSONValue) async throws {
        try await perform(.json(.patch, "/v4/me/profile", patch))
    }

    /// Uploads a JPEG of `width` × `height` pixels for your profile. Grindr cuts
    /// the square thumbnail from its centre. The photo is not shown until it is
    /// added with ``setProfilePhotos(_:)``.
    public func uploadProfilePhoto(_ jpeg: Data, width: Int, height: Int) async throws -> ProfilePhoto {
        let side = min(width, height)
        let left = (width - side) / 2
        let top = (height - side) / 2
        // Bottom, left, right, top; a thumbnail that isn't square is silently dropped.
        let thumbnail = "\(top + side),\(left),\(left + side),\(top)"
        let request = APIRequest(
            .post, "/v4/media/upload",
            query: [
                URLQueryItem(name: "takenOnGrindr", value: "false"),
                URLQueryItem(name: "thumbCoords", value: thumbnail),
            ],
            body: .bytes(contentType: "application/octet-stream", jpeg))
        return try await decode(UploadedProfilePhoto.self, request).photo
    }

    /// Sets your profile photos, the first one being the main photo.
    public func setProfilePhotos(_ mediaHashes: [String]) async throws {
        try await perform(
            .json(
                .put, "/v3/me/profile/images",
                .object([
                    "primaryImageHash": .optional(mediaHashes.first),
                    "secondaryImageHashes": .strings(mediaHashes.dropFirst()),
                ])))
    }

    /// Removes photos from your profile and deletes them from Grindr's servers.
    public func deleteProfilePhotos(_ mediaHashes: [String]) async throws {
        guard !mediaHashes.isEmpty else { return }
        try await perform(
            .json(
                .delete, "/v3/me/profile/images", .object(["media_hashes": .strings(mediaHashes)])))
    }

    /// Records that you viewed a profile, as the official app does when one is opened.
    public func recordView(of id: ProfileID) async throws {
        try await perform(
            .json(.post, "/v5/views/\(id)", .object(["source": .string("UNKNOWN"), "foundVia": .null])))
    }

    public func setFavorite(_ id: ProfileID, _ isFavorite: Bool) async throws {
        try await perform(APIRequest(isFavorite ? .post : .delete, "/v3/me/favorites/\(id)"))
    }

    public func genders() async throws -> [Gender] {
        try await decode(LossyArray<Gender>.self, APIRequest(.get, "/public/v2/genders")).elements
    }

    /// Every profile tag, in the device's language.
    public func profileTags() async throws -> ProfileTagCatalog {
        try await decode(ProfileTagCatalog.self, APIRequest(.get, "/v1/tags"))
    }

    public func pronouns() async throws -> [Pronoun] {
        try await decode(LossyArray<Pronoun>.self, APIRequest(.get, "/v1/pronouns")).elements
    }

    // MARK: Safety

    public func block(_ id: ProfileID) async throws {
        try await perform(APIRequest(.post, "/v3/me/blocks/\(id)"))
    }

    public func unblock(_ id: ProfileID) async throws {
        try await perform(APIRequest(.delete, "/v3/me/blocks/\(id)"))
    }

    public func blockedProfiles() async throws -> [BlockedProfile] {
        struct Response: Decodable { var blocking: [BlockedProfile] }
        return try await decode(Response.self, APIRequest(.get, "/v3.1/me/blocks")).blocking
    }

    /// Hides a profile from your grid without blocking it.
    public func hide(_ id: ProfileID) async throws {
        try await perform(APIRequest(.post, "/v1/me/hides/\(id)"))
    }

    public func report(_ id: ProfileID, _ report: ProfileReport) async throws {
        try await perform(.json(.post, "/v4/flags/\(id)", report.requestBody))
    }

    // MARK: Interest

    /// Sends a tap. Returns whether the tap is mutual.
    @discardableResult
    public func sendTap(_ type: TapType, to id: ProfileID) async throws -> Bool {
        struct Response: Decodable { var isMutual: Bool? }
        let request = try APIRequest.json(
            .post, "/v2/taps/add", .object(["recipientId": .int(id), "tapType": .int(type.rawValue)]))
        return try await decode(Response.self, request).isMutual ?? false
    }

    public func receivedTaps() async throws -> [Tap] {
        return try await decode(LossyProfiles<Tap>.self, APIRequest(.get, "/v2/taps/received")).profiles
    }

    public func profileViews() async throws -> ProfileViews {
        try await decode(ProfileViews.self, APIRequest(.get, "/v7/views/list"))
    }

    // MARK: Messaging

    /// A page of the inbox; pages start at 1.
    public func inbox(page: Int = 1, filter: InboxFilter = InboxFilter()) async throws -> InboxPage {
        let path = "/v4/inbox?page=\(page)"
        let request =
            filter.isDefault
            ? APIRequest(.post, path) : try APIRequest.json(.post, path, filter.requestBody)
        return try await decode(InboxPage.self, request)
    }

    /// A page of a conversation, newest first. Pass the previous page's
    /// ``MessagePage/nextPageKey`` for older messages.
    public func messages(in conversationID: String, pageKey: String? = nil) async throws
        -> MessagePage
    {
        var query = [URLQueryItem(name: "profile", value: "true")]
        if let pageKey { query.append(URLQueryItem(name: "pageKey", value: pageKey)) }
        return try await decode(
            MessagePage.self,
            APIRequest(.get, "/v5/chat/conversation/\(conversationID)/message", query: query))
    }

    public func send(_ message: OutgoingMessage, to id: ProfileID) async throws -> Message {
        try await decode(
            Message.self, .json(.post, "/v4/chat/message/send", message.requestBody(to: id)))
    }

    /// Uploads a photo to send with ``OutgoingMessage/image(mediaID:)``.
    public func uploadChatPhoto(_ data: Data, contentType: String = "image/jpeg") async throws
        -> UploadedMedia
    {
        let request = APIRequest(
            .post, "/v5/chat/media/upload?takenOnGrindr=false",
            body: .bytes(contentType: contentType, data))
        return try await decode(UploadedMedia.self, request)
    }

    /// Marks a conversation read up to and including `messageID`.
    public func markRead(_ conversationID: String, through messageID: String) async throws {
        try await perform(
            APIRequest(.post, "/v4/chat/conversation/\(conversationID)/read/\(messageID)"))
    }

    /// Removes a conversation from your inbox; the other side keeps it.
    public func deleteConversation(_ conversationID: String) async throws {
        try await perform(APIRequest(.delete, "/v4/chat/conversation/\(conversationID)"))
    }

    public func setPinned(_ conversationID: String, _ isPinned: Bool) async throws {
        try await perform(
            APIRequest(.post, "/v4/chat/conversation/\(conversationID)/\(isPinned ? "pin" : "unpin")"))
    }

    public func setMuted(_ conversationID: String, _ isMuted: Bool) async throws {
        try await perform(
            APIRequest(.post, "/v1/push/conversation/\(conversationID)/\(isMuted ? "mute" : "unmute")"))
    }

    /// Unsends a message for both sides.
    public func unsend(_ messageID: String, in conversationID: String) async throws {
        try await perform(messageAction("/v4/chat/message/unsend", messageID, conversationID))
    }

    /// Deletes a message for you only.
    public func deleteMessage(_ messageID: String, in conversationID: String) async throws {
        try await perform(messageAction("/v4/chat/message/delete", messageID, conversationID))
    }

    public func react(
        to messageID: String, in conversationID: String, type: Int = MessageReaction.heart
    )
        async throws
    {
        try await perform(
            .json(
                .post, "/v4/chat/message/reaction",
                .object([
                    "conversationId": .string(conversationID), "messageId": .string(messageID),
                    "reactionType": .int(type),
                ])))
    }

    // MARK: Plumbing

    private func messageAction(_ path: String, _ messageID: String, _ conversationID: String) throws
        -> APIRequest
    {
        try .json(
            .post, path,
            .object(["conversationId": .string(conversationID), "messageId": .string(messageID)]))
    }

    @discardableResult
    func perform(_ request: APIRequest) async throws -> APIResponse {
        let response = try await transport.send(request)
        guard response.isSuccess else { throw GrindrError.from(response) }
        return response
    }

    func decode<T: Decodable>(_ type: T.Type, _ request: APIRequest) async throws -> T {
        let response = try await perform(request)
        do {
            return try JSON.decode(type, from: response.body)
        } catch {
            throw GrindrError.invalidResponse("\(request.method.rawValue) \(request.path): \(error)")
        }
    }
}

/// A response with a `profiles` array; entries this version can't read are skipped.
private struct LossyProfiles<Element: Decodable>: Decodable {
    var profiles: [Element]

    enum CodingKeys: String, CodingKey { case profiles }

    init(from decoder: any Decoder) throws {
        profiles = try decoder.container(keyedBy: CodingKeys.self).lossyArray(of: Element.self, forKey: .profiles)
    }
}
