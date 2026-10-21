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
    /// A place you are looking around instead of where you are.
    public private(set) var exploring: ExplorePlace?

    @ObservationIgnored weak var session: AccountSession?
    @ObservationIgnored private let api: GrindrAPI
    @ObservationIgnored private let location: any LocationProviding
    /// Remembers applied filters for the next launch; the explored place is not kept.
    @ObservationIgnored private let saveFilters: (BrowseFilters) -> Void
    @ObservationIgnored private var nextPage: Int?
    /// Where the loaded pages come from, for the next page.
    @ObservationIgnored private var area: BrowseArea?
    /// Where you were when the grid last loaded nearby.
    @ObservationIgnored private var geohash: String?
    /// Bumped on every reload, so a page that arrives late for an old query is dropped.
    @ObservationIgnored private var generation = 0

    init(
        api: GrindrAPI, location: any LocationProviding, filters: BrowseFilters = BrowseFilters(),
        saveFilters: @escaping (BrowseFilters) -> Void = { _ in }
    ) {
        self.api = api
        self.location = location
        self.filters = filters
        self.saveFilters = saveFilters
    }

    public var canLoadMore: Bool { nextPage != nil }

    /// Loads the grid unless it is already loaded.
    public func loadIfNeeded() async {
        guard state.needsLoad else { return }
        await refresh()
    }

    /// Reloads the first page, finding you again unless you are exploring.
    public func refresh() async {
        generation += 1
        let generation = generation
        if profiles.isEmpty { state = .loading }
        do {
            let area: BrowseArea
            if let exploring {
                area = .exploring(geohash: exploring.geohash)
            } else {
                area = .nearby(geohash: try await location.currentGeohash())
            }
            let page = try await api.cascade(area, filters: filters, page: nil)
            guard generation == self.generation else { return }
            self.area = area
            if case .nearby(let geohash) = area { self.geohash = geohash }
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
        saveFilters(filters)
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
        guard !isLoadingMore, let page = nextPage, let area, state == .loaded else { return }
        let generation = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await api.cascade(area, filters: filters, page: page)
            guard generation == self.generation else { return }
            profiles += next.profiles.uniqued(excluding: profiles.map(\.id))
            nextPage = next.nextPage
        } catch {
            // The grid stays usable; scrolling to the end again retries.
        }
    }

    /// Where you were when the grid last loaded, to start a map at.
    public var currentPlace: ExplorePlace? {
        geohash.flatMap(Geohash.decode).map { ExplorePlace(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Shows the profiles around `place` instead of around you, or around you
    /// again when `nil`.
    public func explore(_ place: ExplorePlace?) async {
        guard place != exploring else { return }
        exploring = place
        profiles = []
        nextPage = nil
        await refresh()
    }

    // MARK: Updates from elsewhere

    func remove(_ profileID: ProfileID) {
        profiles.removeAll { $0.id == profileID }
    }

    func setFavorite(_ profileID: ProfileID, _ isFavorite: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].isFavorite = isFavorite
    }

    /// Unread messages from a tile's profile: the inbox's count, which follows new
    /// messages and reads, or the grid's from when it loaded if the inbox doesn't
    /// have the conversation.
    public func unreadCount(of profile: GridProfile) -> Int {
        session?.inbox.unreadCount(from: profile.id) ?? profile.unreadCount
    }
}
