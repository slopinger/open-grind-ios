import Foundation

/// A profile tile in the nearby grid (`GET /v4/cascade`).
public struct GridProfile: Identifiable, Hashable, Sendable, OnlinePresence {
    public var id: ProfileID
    public var displayName: String?
    public var age: Int?
    /// Meters.
    public var distance: Double?
    public var photoURL: URL?
    public var onlineUntil: Date?
    public var lastOnline: Date?
    public var position: SexualPosition?
    public var unreadCount: Int
    public var isFavorite: Bool
    public var hasViewed: Bool
    public var isVisiting: Bool
    public var isPopular: Bool
    /// The server only shows a teaser of this profile without a subscription.
    public var isLocked: Bool

    public init(
        id: ProfileID, displayName: String? = nil, age: Int? = nil, distance: Double? = nil,
        photoURL: URL? = nil,
        onlineUntil: Date? = nil, lastOnline: Date? = nil, position: SexualPosition? = nil,
        unreadCount: Int = 0,
        isFavorite: Bool = false, hasViewed: Bool = false,
        isVisiting: Bool = false,
        isPopular: Bool = false, isLocked: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.age = age
        self.distance = distance
        self.photoURL = photoURL
        self.onlineUntil = onlineUntil
        self.lastOnline = lastOnline
        self.position = position
        self.unreadCount = unreadCount
        self.isFavorite = isFavorite
        self.hasViewed = hasViewed
        self.isVisiting = isVisiting
        self.isPopular = isPopular
        self.isLocked = isLocked
    }

    private enum CodingKeys: String, CodingKey {
        case profileId, displayName, age, distanceMeters, primaryImageUrl, onlineUntil, lastOnline
        case sexualPosition, unreadCount, favorite, viewed, isVisiting, isPopular
    }

    /// A cascade item's `data`.
    fileprivate init(from decoder: any Decoder, isLocked: Bool) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeFlexibleInt(forKey: .profileId),
            displayName: container.lenient(String.self, forKey: .displayName),
            age: container.lenient(Int.self, forKey: .age),
            distance: container.lenient(Double.self, forKey: .distanceMeters),
            photoURL: container.lenient(String.self, forKey: .primaryImageUrl).flatMap(MediaURL.validated),
            onlineUntil: container.timestamp(forKey: .onlineUntil),
            lastOnline: container.timestamp(forKey: .lastOnline),
            position: SexualPosition.known(container.lenient(Int.self, forKey: .sexualPosition)),
            unreadCount: container.lenient(Int.self, forKey: .unreadCount) ?? 0,
            isFavorite: container.flag(forKey: .favorite),
            hasViewed: container.flag(forKey: .viewed),
            isVisiting: container.flag(forKey: .isVisiting),
            isPopular: container.flag(forKey: .isPopular),
            isLocked: isLocked)
    }
}

/// One page of the nearby grid.
public struct CascadePage: Sendable, Hashable {
    public var profiles: [GridProfile]
    public var nextPage: Int?

    public init(profiles: [GridProfile], nextPage: Int?) {
        self.profiles = profiles
        self.nextPage = nextPage
    }
}

extension CascadePage: Decodable {
    enum CodingKeys: String, CodingKey {
        case items, nextPage
    }

    /// A cascade item. Only profile items are kept; ads, upsells and items
    /// this version does not know decode to `nil` instead of failing the page.
    private struct Item: Decodable {
        var profile: GridProfile?

        enum CodingKeys: String, CodingKey {
            case type, data
        }

        enum SponsoredKeys: String, CodingKey {
            case alternativeProfile
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch container.lenient(String.self, forKey: .type) {
            case "full_profile_v1", "smart_boost_profile_v1":
                profile = try? GridProfile(from: container.superDecoder(forKey: .data), isLocked: false)
            case "partial_profile_v1":
                profile = try? GridProfile(from: container.superDecoder(forKey: .data), isLocked: true)
            default:
                profile = nil
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = container.lossyArray(of: Item.self, forKey: .items)
        var seen = Set<ProfileID>()
        profiles = items.compactMap(\.profile).filter { seen.insert($0.id).inserted }
        nextPage = container.lenient(Int.self, forKey: .nextPage)
    }
}

/// The grid filters a user can set. Ranges at their outer bounds are not
/// sent, matching the official app.
public struct BrowseFilters: Hashable, Sendable, Codable {
    public static let ageBounds = 18...99
    /// Centimeters.
    public static let heightBounds = 121.0...241.0
    /// Grams.
    public static let weightBounds = 40_823.0...272_156.0

    public var onlineOnly = false
    public var photosOnly = false
    public var facePhotosOnly = false
    public var favoritesOnly = false
    public var notChattedToday = false
    public var ages: ClosedRange<Int> = BrowseFilters.ageBounds
    public var heights: ClosedRange<Double> = BrowseFilters.heightBounds
    public var weights: ClosedRange<Double> = BrowseFilters.weightBounds
    public var positions: Set<SexualPosition> = []
    public var lookingFor: Set<LookingFor> = []
    public var tribes: Set<Tribe> = []
    public var bodyTypes: Set<BodyType> = []
    public var relationshipStatuses: Set<RelationshipStatus> = []
    public var meetAt: Set<MeetAt> = []
    public var acceptsNSFWPics: Set<AcceptsNSFWPics> = []
    /// Keys of ``ProfileTag``s; matching profiles have at least one of them.
    public var tags: Set<String> = []

    public init() {}

    /// No filter is set.
    public var isDefault: Bool { self == BrowseFilters() }

    /// How many filters are set, for a badge on the filter button.
    public var activeCount: Int {
        [
            onlineOnly, photosOnly, facePhotosOnly, favoritesOnly, notChattedToday,
            ages != Self.ageBounds, heights != Self.heightBounds, weights != Self.weightBounds,
            !positions.isEmpty, !lookingFor.isEmpty, !tribes.isEmpty, !bodyTypes.isEmpty,
            !relationshipStatuses.isEmpty, !meetAt.isEmpty, !acceptsNSFWPics.isEmpty, !tags.isEmpty,
        ].filter { $0 }.count
    }

    /// Query items for `GET /v4/cascade`.
    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        func flag(_ name: String, _ isOn: Bool) {
            if isOn { items.append(URLQueryItem(name: name, value: "true")) }
        }
        func list(_ name: String, _ values: some Collection<some ProfileAttribute>) {
            guard !values.isEmpty else { return }
            let ids = values.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
            items.append(URLQueryItem(name: name, value: ids))
        }
        func number(_ value: Double) -> String {
            value.rounded() == value ? String(Int(value)) : String(value)
        }

        flag("onlineOnly", onlineOnly)
        flag("favorites", favoritesOnly)
        flag("photoOnly", photosOnly)
        flag("faceOnly", facePhotosOnly)
        flag("notRecentlyChatted", notChattedToday)
        if ages != Self.ageBounds {
            items.append(URLQueryItem(name: "ageMin", value: String(ages.lowerBound)))
            items.append(URLQueryItem(name: "ageMax", value: String(ages.upperBound)))
        }
        if heights != Self.heightBounds {
            items.append(URLQueryItem(name: "heightCmMin", value: number(heights.lowerBound)))
            items.append(URLQueryItem(name: "heightCmMax", value: number(heights.upperBound)))
        }
        if weights != Self.weightBounds {
            items.append(
                URLQueryItem(name: "weightGramsMin", value: number(weights.lowerBound.rounded())))
            items.append(
                URLQueryItem(name: "weightGramsMax", value: number(weights.upperBound.rounded())))
        }
        list("sexualPositions", positions)
        list("lookingFor", lookingFor)
        list("tribes", tribes)
        list("bodyTypes", bodyTypes)
        list("relationshipStatuses", relationshipStatuses)
        list("meetAt", meetAt)
        list("nsfwPics", acceptsNSFWPics)
        if !tags.isEmpty {
            items.append(URLQueryItem(name: "tags", value: tags.sorted().joined(separator: ",")))
        }
        return items
    }
}

/// A place to browse other than where you are.
public struct ExplorePlace: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// What to call the place, e.g. a city from reverse geocoding.
    public var name: String?

    public init(latitude: Double, longitude: Double, name: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }

    var geohash: String { Geohash.encode(latitude: latitude, longitude: longitude) }
}

extension Profile {
    /// What the grid already knows about a profile, to show while it loads.
    public init(_ tile: GridProfile) {
        self.init(
            id: tile.id, displayName: tile.displayName, age: tile.age, distance: tile.distance,
            onlineUntil: tile.onlineUntil, lastSeen: tile.lastOnline,
            photos: tile.photoURL.flatMap(MediaURL.mediaHash(ofThumbnail:)).map { [ProfilePhoto(mediaHash: $0)] } ?? [],
            position: tile.position, isFavorite: tile.isFavorite, isVisiting: tile.isVisiting,
            unreadCount: tile.unreadCount)
    }
}
