import Foundation

/// A profile tile in the nearby grid (`GET /v4/cascade`).
public struct GridProfile: Identifiable, Hashable, Sendable {
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
    public var hasChatted: Bool
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
        isFavorite: Bool = false, hasChatted: Bool = false, hasViewed: Bool = false,
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
        self.hasChatted = hasChatted
        self.hasViewed = hasViewed
        self.isVisiting = isVisiting
        self.isPopular = isPopular
        self.isLocked = isLocked
    }

    public func isOnline(at date: Date = .now) -> Bool {
        onlineUntil.map { $0 > date } ?? false
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
                profile = container.lenient(ProfileData.self, forKey: .data)?.profile(isLocked: false)
            case "partial_profile_v1":
                profile = container.lenient(ProfileData.self, forKey: .data)?.profile(isLocked: true)
            default:
                profile = nil
            }
        }
    }

    private struct ProfileData: Decodable {
        var profileId: Int
        var displayName: String?
        var age: Int?
        var distanceMeters: Double?
        var primaryImageUrl: String?
        var onlineUntil: Double?
        var lastOnline: Double?
        var sexualPosition: Int?
        var unreadCount: Int?
        var favorite: Bool?
        var chatted: Bool?
        var viewed: Bool?
        var isVisiting: Bool?
        var isPopular: Bool?

        enum CodingKeys: String, CodingKey {
            case profileId, displayName, age, distanceMeters, primaryImageUrl, onlineUntil, lastOnline
            case sexualPosition, unreadCount, favorite, chatted, viewed, isVisiting, isPopular
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profileId = try container.decodeFlexibleInt(forKey: .profileId)
            displayName = container.lenient(String.self, forKey: .displayName)
            age = container.lenient(Int.self, forKey: .age)
            distanceMeters = container.lenient(Double.self, forKey: .distanceMeters)
            primaryImageUrl = container.lenient(String.self, forKey: .primaryImageUrl)
            onlineUntil = container.lenient(Double.self, forKey: .onlineUntil)
            lastOnline = container.lenient(Double.self, forKey: .lastOnline)
            sexualPosition = container.lenient(Int.self, forKey: .sexualPosition)
            unreadCount = container.lenient(Int.self, forKey: .unreadCount)
            favorite = container.lenient(Bool.self, forKey: .favorite)
            chatted = container.lenient(Bool.self, forKey: .chatted)
            viewed = container.lenient(Bool.self, forKey: .viewed)
            isVisiting = container.lenient(Bool.self, forKey: .isVisiting)
            isPopular = container.lenient(Bool.self, forKey: .isPopular)
        }

        func profile(isLocked: Bool) -> GridProfile {
            func date(_ milliseconds: Double?) -> Date? {
                milliseconds.flatMap { $0 > 0 ? Date(milliseconds: Int64($0)) : nil }
            }
            return GridProfile(
                id: profileId, displayName: displayName, age: age, distance: distanceMeters,
                photoURL: primaryImageUrl.flatMap(MediaURL.validated), onlineUntil: date(onlineUntil),
                lastOnline: date(lastOnline), position: SexualPosition.known(sexualPosition),
                unreadCount: unreadCount ?? 0, isFavorite: favorite ?? false, hasChatted: chatted ?? false,
                hasViewed: viewed ?? false, isVisiting: isVisiting ?? false, isPopular: isPopular ?? false,
                isLocked: isLocked)
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

    public init() {}

    /// No filter is set.
    public var isDefault: Bool { self == BrowseFilters() }

    /// How many filters are set, for a badge on the filter button.
    public var activeCount: Int {
        [
            onlineOnly, photosOnly, facePhotosOnly, favoritesOnly, notChattedToday,
            ages != Self.ageBounds, heights != Self.heightBounds, weights != Self.weightBounds,
            !positions.isEmpty, !lookingFor.isEmpty, !tribes.isEmpty, !bodyTypes.isEmpty,
            !relationshipStatuses.isEmpty, !meetAt.isEmpty, !acceptsNSFWPics.isEmpty,
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
        return items
    }
}
