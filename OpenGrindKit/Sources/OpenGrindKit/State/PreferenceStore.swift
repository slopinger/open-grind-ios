import Foundation

/// Settings remembered per account across launches.
public protocol PreferenceStore: Sendable {
    func browseFilters(for profileID: ProfileID) -> BrowseFilters?
    /// `nil` forgets them.
    func saveBrowseFilters(_ filters: BrowseFilters?, for profileID: ProfileID)
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

    private static func filtersKey(_ profileID: ProfileID) -> String { "browseFilters.\(profileID)" }
}
