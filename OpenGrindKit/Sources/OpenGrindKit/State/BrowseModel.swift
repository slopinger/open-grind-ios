import Foundation
import Observation

/// The nearby grid.
@MainActor
@Observable
public final class BrowseModel {
    public private(set) var profiles: [GridProfile] = []
    public private(set) var state: LoadState = .idle
    public private(set) var isLoadingMore = false
    public private(set) var filters = BrowseFilters()
    /// The tags to filter by, once ``loadTagCatalog()`` has run.
    public private(set) var tagCatalog: ProfileTagCatalog?
    public private(set) var tagCatalogState: LoadState = .idle
    /// A place you are looking around instead of where you are.
    public private(set) var exploring: ExplorePlace?

    @ObservationIgnored weak var session: AccountSession?
    @ObservationIgnored private let api: GrindrAPI
    @ObservationIgnored private let location: any LocationProviding
    @ObservationIgnored private var nextPage: Int?
    @ObservationIgnored private var geohash: String?
    /// Bumped on every reload, so a page that arrives late for an old query is dropped.
    @ObservationIgnored private var generation = 0

    init(api: GrindrAPI, location: any LocationProviding) {
        self.api = api
        self.location = location
    }

    public var canLoadMore: Bool { nextPage != nil }

    /// Loads the grid unless it is already loaded.
    public func loadIfNeeded() async {
        guard state == .idle || state.failure != nil else { return }
        await refresh()
    }

    /// Finds you again and reloads the first page.
    public func refresh() async {
        generation += 1
        let generation = generation
        if profiles.isEmpty { state = .loading }
        do {
            let geohash = try await location.currentGeohash()
            let page = try await api.cascade(
                near: geohash, exploring: exploring?.geohash, filters: filters, page: nil)
            guard generation == self.generation else { return }
            self.geohash = geohash
            profiles = page.profiles
            nextPage = page.nextPage
            state = .loaded
        } catch {
            guard generation == self.generation else { return }
            state = .failed(Failure(error))
        }
    }

    public func apply(_ filters: BrowseFilters) async {
        guard filters != self.filters else { return }
        self.filters = filters
        profiles = []
        nextPage = nil
        await refresh()
    }

    /// Loads the next page once `profile` is among the last tiles on screen.
    public func loadMoreIfNeeded(after profile: GridProfile) async {
        guard let index = profiles.lastIndex(where: { $0.id == profile.id }),
            index >= profiles.count - 12
        else {
            return
        }
        await loadMore()
    }

    public func loadMore() async {
        guard !isLoadingMore, let page = nextPage, let geohash, state == .loaded else { return }
        let generation = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await api.cascade(
                near: geohash, exploring: exploring?.geohash, filters: filters, page: page)
            guard generation == self.generation else { return }
            let known = Set(profiles.map(\.id))
            profiles += next.profiles.filter { !known.contains($0.id) }
            nextPage = next.nextPage
        } catch {
            // The grid stays usable; scrolling to the end again retries.
        }
    }

    /// Shows the profiles around `place` instead of around you, or around you
    /// again when `nil`.
    /// Where you were when the grid last loaded, to start a map at.
    public var currentPlace: ExplorePlace? {
        geohash.flatMap(Geohash.decode).map { ExplorePlace(latitude: $0.latitude, longitude: $0.longitude) }
    }

    public func explore(_ place: ExplorePlace?) async {
        guard place != exploring else { return }
        exploring = place
        profiles = []
        nextPage = nil
        await refresh()
    }

    /// Loads the tags the filters offer, unless they are already loaded.
    public func loadTagCatalog() async {
        guard tagCatalog == nil, !tagCatalogState.isLoading else { return }
        tagCatalogState = .loading
        do {
            tagCatalog = try await api.profileTags()
            tagCatalogState = .loaded
        } catch {
            tagCatalogState = .failed(Failure(error))
        }
    }

    // MARK: Updates from elsewhere

    func remove(_ profileID: ProfileID) {
        profiles.removeAll { $0.id == profileID }
    }

    func setFavorite(_ profileID: ProfileID, _ isFavorite: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].isFavorite = isFavorite
    }

    func handle(_ event: RealtimeEvent) {
        switch event {
        case .message(let message):
            guard let index = profiles.firstIndex(where: { $0.id == message.senderID }) else { return }
            profiles[index].hasChatted = true
            if session?.inbox.openConversationID != message.conversationID {
                profiles[index].unreadCount += 1
            }
        case .conversationRead(let conversationID, let reader, _) where reader == session?.profileID:
            guard
                let other = conversationID.split(separator: ":").compactMap({ Int($0) }).first(where: {
                    $0 != reader
                }), let index = profiles.firstIndex(where: { $0.id == other })
            else { return }
            profiles[index].unreadCount = 0
        default:
            break
        }
    }
}
