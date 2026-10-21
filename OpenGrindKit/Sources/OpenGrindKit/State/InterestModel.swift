import Foundation
import Observation

/// Taps you received and who viewed your profile.
@MainActor
@Observable
public final class InterestModel {
    public private(set) var taps: [Tap] = []
    public private(set) var views = ProfileViews(viewers: [])
    public private(set) var tapsState: LoadState = .idle
    public private(set) var viewsState: LoadState = .idle
    /// New taps and views since the Interest tab was last on screen.
    public private(set) var unseenCount = 0
    /// Whether the Interest tab is on screen; nothing that arrives meanwhile is unseen.
    public var isOnScreen = false {
        didSet { if isOnScreen { unseenCount = 0 } }
    }

    @ObservationIgnored private let api: GrindrAPI
    @ObservationIgnored private let me: ProfileID
    /// Views often come in bursts; the list is reloaded once they settle.
    @ObservationIgnored private let viewsRefresh = Debouncer(.milliseconds(600))

    init(api: GrindrAPI, me: ProfileID) {
        self.api = api
        self.me = me
    }

    public func loadIfNeeded() async {
        async let taps: Void = tapsState.needsLoad ? refreshTaps() : ()
        async let views: Void = viewsState.needsLoad ? refreshViews() : ()
        _ = await (taps, views)
    }

    public func refresh() async {
        async let taps: Void = refreshTaps()
        async let views: Void = refreshViews()
        _ = await (taps, views)
    }

    public func refreshTaps() async {
        if taps.isEmpty { tapsState = .loading }
        do {
            taps = try await api.receivedTaps().sorted { $0.date > $1.date }
            tapsState = .loaded
        } catch {
            if taps.isEmpty { tapsState = .failed(Failure(error)) }
        }
    }

    public func refreshViews() async {
        if views.viewers.isEmpty { viewsState = .loading }
        do {
            let views = try await api.profileViews()
            self.views = ProfileViews(
                viewers: views.viewers.sorted {
                    ($0.lastViewed ?? .distantPast) > ($1.lastViewed ?? .distantPast)
                },
                hiddenCount: views.hiddenCount)
            viewsState = .loaded
        } catch {
            if views.viewers.isEmpty { viewsState = .failed(Failure(error)) }
        }
    }

    func remove(_ profileID: ProfileID) {
        taps.removeAll { $0.profileID == profileID }
        views.viewers.removeAll { $0.profileID == profileID }
    }

    func handle(_ event: RealtimeEvent) {
        switch event {
        case .tapReceived(let tap) where tap.profileID != me:
            taps.removeAll { $0.profileID == tap.profileID }
            taps.insert(tap, at: 0)
            if !isOnScreen { unseenCount += 1 }
        case .profileViewed(let viewer, _, _) where viewer != me:
            if !isOnScreen { unseenCount += 1 }
            viewsRefresh.schedule { [weak self] in await self?.refreshViews() }
        default:
            break
        }
    }
}
