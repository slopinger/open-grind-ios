import Foundation
import Observation

/// Everything that belongs to the signed-in account: its API, realtime events
/// and the state of each tab.
@MainActor
@Observable
public final class AccountSession {
    public let profileID: ProfileID
    public let api: GrindrAPI
    public internal(set) var isRealtimeConnected = false

    public let browse: BrowseModel
    public let inbox: InboxModel
    public let interest: InterestModel
    public let me: MeModel
    public let catalogs: CatalogModel

    @ObservationIgnored private var chats: [String: ChatModel] = [:]
    @ObservationIgnored private var lastLocationUpdate: Date?
    @ObservationIgnored private var isUpdatingLocation = false
    @ObservationIgnored private let location: any LocationProviding

    init(
        profileID: ProfileID, api: GrindrAPI, location: any LocationProviding,
        preferences: (any PreferenceStore)? = nil
    ) {
        self.profileID = profileID
        self.api = api
        self.location = location
        browse = BrowseModel(
            api: api, location: location,
            filters: preferences?.browseFilters(for: profileID) ?? BrowseFilters()
        ) { filters in
            preferences?.saveBrowseFilters(filters, for: profileID)
        }
        inbox = InboxModel(api: api, me: profileID)
        interest = InterestModel(api: api, me: profileID)
        catalogs = CatalogModel(api: api)
        me = MeModel(api: api, profileID: profileID, catalogs: catalogs)
        browse.session = self
        inbox.session = self
    }

    func start() {
        Task {
            try? await api.transport.connectRealtime()
        }
        Task { await updateLocationIfNeeded() }
    }

    func stop() {
        chats.removeAll()
    }

    func becameActive() {
        Task { await updateLocationIfNeeded() }
        Task { await inbox.refresh() }
    }

    /// Sends your location to Grindr at most every five minutes, so others see
    /// a current distance.
    func updateLocationIfNeeded() async {
        // Starting and returning to the foreground can ask at the same time.
        guard !isUpdatingLocation else { return }
        if let lastLocationUpdate, Date.now.timeIntervalSince(lastLocationUpdate) < 300 { return }
        isUpdatingLocation = true
        defer { isUpdatingLocation = false }
        guard let geohash = try? await location.currentGeohash(),
            (try? await api.updateLocation(geohash: geohash)) != nil
        else { return }
        lastLocationUpdate = .now
    }

    /// What the Explore map chose: browse `place`, and with `appearThere` also
    /// appear there (your profile moves to it, see ``LocationChoice``). `nil`
    /// goes back to where you are, ending both.
    public func go(to place: ExplorePlace?, appearThere: Bool, location: LocationChoice) async {
        let moves = appearThere || location.place != nil
        location.choose(appearThere ? place : nil)
        guard moves else {
            await browse.explore(place)
            return
        }
        // Where you appear is your nearby grid, so there is nothing to explore then.
        lastLocationUpdate = nil
        async let moved: Void = updateLocationIfNeeded()
        async let grid: Void = browse.explore(appearThere ? nil : place)
        _ = await (moved, grid)
    }

    // MARK: Chats

    /// The chat with `profileID`, shared across screens so drafts and loaded
    /// messages survive navigation.
    public func chat(with profileID: ProfileID, name: String? = nil) -> ChatModel {
        let conversationID = Conversation.id(between: self.profileID, and: profileID)
        if let chat = chats[conversationID] { return chat }
        let chat = ChatModel(
            conversationID: conversationID, otherProfileID: profileID, name: name, api: api,
            me: self.profileID)
        chat.session = self
        chats[conversationID] = chat
        return chat
    }

    public func chat(for conversation: Conversation) -> ChatModel? {
        guard let other = conversation.otherProfileID(me: profileID) else { return nil }
        return chat(with: other, name: conversation.name)
    }

    // MARK: Events

    func receive(_ event: RealtimeEvent) {
        inbox.handle(event)
        interest.handle(event)
        for id in event.conversationIDs {
            chats[id]?.handle(event)
        }
    }

    // MARK: Cross-tab updates

    /// A profile was blocked or hidden: drop it everywhere.
    func forget(_ profileID: ProfileID) {
        browse.remove(profileID)
        inbox.remove(conversationID: Conversation.id(between: self.profileID, and: profileID))
        interest.remove(profileID)
        chats[Conversation.id(between: self.profileID, and: profileID)] = nil
    }

    func favoriteChanged(_ profileID: ProfileID, isFavorite: Bool) {
        browse.setFavorite(profileID, isFavorite)
        inbox.setFavorite(profileID, isFavorite)
    }
}
