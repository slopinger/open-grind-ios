import Foundation

/// A tap someone sent you (`GET /v2/taps/received`).
public struct Tap: Identifiable, Hashable, Sendable, OnlinePresence {
    public var profileID: ProfileID
    public var displayName: String?
    public var photoHash: String?
    /// Meters.
    public var distance: Double?
    public var date: Date
    public var type: TapType?
    /// You tapped each other.
    public var isMutual: Bool
    public var onlineUntil: Date?
    public var isFavorite: Bool
    /// `false` when the profile is hidden behind a subscription.
    public var isViewable: Bool

    public var id: ProfileID { profileID }

    public init(
        profileID: ProfileID, displayName: String? = nil, photoHash: String? = nil,
        distance: Double? = nil,
        date: Date, type: TapType?, isMutual: Bool = false, onlineUntil: Date? = nil,
        isFavorite: Bool = false,
        isViewable: Bool = true
    ) {
        self.profileID = profileID
        self.displayName = displayName
        self.photoHash = photoHash
        self.distance = distance
        self.date = date
        self.type = type
        self.isMutual = isMutual
        self.onlineUntil = onlineUntil
        self.isFavorite = isFavorite
        self.isViewable = isViewable
    }

}

extension Tap: Decodable {
    enum CodingKeys: String, CodingKey {
        case profileId, displayName, profileImageMediaHash, distance, timestamp, tapType, isMutual,
            onlineUntil
        case isFavorite, isViewable
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try container.decodeFlexibleInt(forKey: .profileId)
        displayName = container.lenient(String.self, forKey: .displayName)
        photoHash = container.lenient(String.self, forKey: .profileImageMediaHash)
        distance = container.lenient(Double.self, forKey: .distance)
        date = container.timestamp(forKey: .timestamp) ?? .distantPast
        type = TapType.known(container.lenient(Int.self, forKey: .tapType))
        isMutual = container.flag(forKey: .isMutual)
        onlineUntil = container.timestamp(forKey: .onlineUntil)
        isFavorite = container.flag(forKey: .isFavorite)
        isViewable = container.flag(forKey: .isViewable, missing: true)
    }
}

/// Someone who viewed your profile (`GET /v7/views/list`).
public struct ProfileViewer: Identifiable, Hashable, Sendable, OnlinePresence {
    public var profileID: ProfileID
    public var displayName: String?
    public var photoHash: String?
    /// Meters.
    public var distance: Double?
    public var lastViewed: Date?
    public var viewCount: Int
    public var onlineUntil: Date?
    public var isFavorite: Bool

    public var id: ProfileID { profileID }

    public init(
        profileID: ProfileID, displayName: String? = nil, photoHash: String? = nil,
        distance: Double? = nil,
        lastViewed: Date? = nil, viewCount: Int = 1, onlineUntil: Date? = nil, isFavorite: Bool = false
    ) {
        self.profileID = profileID
        self.displayName = displayName
        self.photoHash = photoHash
        self.distance = distance
        self.lastViewed = lastViewed
        self.viewCount = viewCount
        self.onlineUntil = onlineUntil
        self.isFavorite = isFavorite
    }

}

/// Your profile views: the viewers you may see, and how many more are hidden
/// behind a subscription.
public struct ProfileViews: Hashable, Sendable {
    public var viewers: [ProfileViewer]
    public var hiddenCount: Int

    public init(viewers: [ProfileViewer], hiddenCount: Int = 0) {
        self.viewers = viewers
        self.hiddenCount = hiddenCount
    }
}

extension ProfileViews: Decodable {
    enum CodingKeys: String, CodingKey {
        case profiles, previews
    }

    private struct Viewer: Decodable {
        var value: ProfileViewer

        enum CodingKeys: String, CodingKey {
            case profileId, displayName, profileImageMediaHash, distance, lastViewed, viewedCount,
                onlineUntil
            case isFavorite
        }

        struct Count: Decodable { var totalCount: Int }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = ProfileViewer(
                profileID: try container.decodeFlexibleInt(forKey: .profileId),
                displayName: container.lenient(String.self, forKey: .displayName),
                photoHash: container.lenient(String.self, forKey: .profileImageMediaHash),
                distance: container.lenient(Double.self, forKey: .distance),
                lastViewed: container.timestamp(forKey: .lastViewed),
                viewCount: container.lenient(Count.self, forKey: .viewedCount)?.totalCount ?? 1,
                onlineUntil: container.timestamp(forKey: .onlineUntil),
                isFavorite: container.flag(forKey: .isFavorite))
        }
    }

    private struct Preview: Decodable {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewers = container.lossyArray(of: Viewer.self, forKey: .profiles).map(\.value)
        hiddenCount = container.lossyArray(of: Preview.self, forKey: .previews).count
    }
}
