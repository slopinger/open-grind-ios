import Foundation

/// Settings remembered across launches.
public protocol PreferenceStore: Sendable {
    /// Per account.
    func browseFilters(for profileID: ProfileID) -> BrowseFilters?
    /// `nil` forgets them.
    func saveBrowseFilters(_ filters: BrowseFilters?, for profileID: ProfileID)
    /// The place you appear at instead of your device's location (``LocationChoice``),
    /// for the app rather than one account: signing in already uses it.
    func chosenPlace() -> ExplorePlace?
    /// `nil` goes back to the device's location.
    func saveChosenPlace(_ place: ExplorePlace?)
}

/// Keeps preferences in `UserDefaults`.
public struct DefaultsPreferenceStore: PreferenceStore, @unchecked Sendable {
    // UserDefaults is thread-safe.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func browseFilters(for profileID: ProfileID) -> BrowseFilters? {
        // Filters saved by an older version that no longer decode fall back to the defaults.
        defaults.data(forKey: Self.filtersKey(profileID)).flatMap {
            try? JSON.decode(BrowseFilters.self, from: $0)
        }
    }

    public func saveBrowseFilters(_ filters: BrowseFilters?, for profileID: ProfileID) {
        let key = Self.filtersKey(profileID)
        if let filters, let data = try? JSON.encode(filters) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func chosenPlace() -> ExplorePlace? {
        defaults.data(forKey: Self.chosenPlaceKey).flatMap { try? JSON.decode(ExplorePlace.self, from: $0) }
    }

    public func saveChosenPlace(_ place: ExplorePlace?) {
        if let place, let data = try? JSON.encode(place) {
            defaults.set(data, forKey: Self.chosenPlaceKey)
        } else {
            defaults.removeObject(forKey: Self.chosenPlaceKey)
        }
    }

    private static func filtersKey(_ profileID: ProfileID) -> String { "browseFilters.\(profileID)" }
    private static let chosenPlaceKey = "chosenPlace"
}
