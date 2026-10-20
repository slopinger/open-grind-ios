import Foundation

/// A photo on a profile.
public struct ProfilePhoto: Hashable, Sendable, Identifiable {
    /// 40 hex characters; the photo's address on the CDN.
    public var mediaHash: String
    /// `true` until moderation has approved the photo. Only you see these.
    public var isPendingReview: Bool

    public var id: String { mediaHash }

    public init(mediaHash: String, isPendingReview: Bool = false) {
        self.mediaHash = mediaHash
        self.isPendingReview = isPendingReview
    }
}

/// A full profile, as `GET /v7/profiles/{id}` returns it.
public struct Profile: Identifiable, Hashable, Sendable {
    public var id: ProfileID
    public var displayName: String?
    public var aboutMe: String?
    public var age: Int?
    public var showsAge: Bool
    /// Meters. `nil` when the profile hides its distance.
    public var distance: Double?
    public var isDistanceApproximate: Bool
    public var showsDistance: Bool
    public var onlineUntil: Date?
    public var lastSeen: Date?
    public var photos: [ProfilePhoto]
    /// Centimeters.
    public var height: Double?
    /// Grams.
    public var weight: Double?
    public var position: SexualPosition?
    public var bodyType: BodyType?
    public var ethnicity: Ethnicity?
    public var relationshipStatus: RelationshipStatus?
    public var tribes: [Tribe]
    public var tribesImInto: [Tribe]
    public var lookingFor: [LookingFor]
    public var meetAt: [MeetAt]
    public var acceptsNSFWPics: AcceptsNSFWPics?
    public var hivStatus: HIVStatus?
    public var lastTested: Date?
    public var sexualHealth: [SexualHealthPractice]
    public var vaccines: [Vaccine]
    public var genderIDs: [Int]
    public var pronounIDs: [Int]
    public var tags: [String]
    public var instagram: String?
    public var isFavorite: Bool
    /// The tap this profile last sent you, if any.
    public var receivedTap: TapType?
    /// Whether you have tapped this profile.
    public var hasBeenTapped: Bool
    public var isNew: Bool
    public var isVisiting: Bool
    public var isRoaming: Bool
    public var unreadCount: Int
    public var showsTribes: Bool
    public var showsPosition: Bool

    public init(
        id: ProfileID, displayName: String? = nil, aboutMe: String? = nil, age: Int? = nil,
        showsAge: Bool = true,
        distance: Double? = nil, isDistanceApproximate: Bool = false, showsDistance: Bool = true,
        onlineUntil: Date? = nil, lastSeen: Date? = nil, photos: [ProfilePhoto] = [],
        height: Double? = nil,
        weight: Double? = nil, position: SexualPosition? = nil, bodyType: BodyType? = nil,
        ethnicity: Ethnicity? = nil, relationshipStatus: RelationshipStatus? = nil,
        tribes: [Tribe] = [],
        tribesImInto: [Tribe] = [], lookingFor: [LookingFor] = [], meetAt: [MeetAt] = [],
        acceptsNSFWPics: AcceptsNSFWPics? = nil, hivStatus: HIVStatus? = nil, lastTested: Date? = nil,
        sexualHealth: [SexualHealthPractice] = [], vaccines: [Vaccine] = [], genderIDs: [Int] = [],
        pronounIDs: [Int] = [], tags: [String] = [], instagram: String? = nil, isFavorite: Bool = false,
        receivedTap: TapType? = nil, hasBeenTapped: Bool = false, isNew: Bool = false,
        isVisiting: Bool = false,
        isRoaming: Bool = false, unreadCount: Int = 0, showsTribes: Bool = true,
        showsPosition: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.aboutMe = aboutMe
        self.age = age
        self.showsAge = showsAge
        self.distance = distance
        self.isDistanceApproximate = isDistanceApproximate
        self.showsDistance = showsDistance
        self.onlineUntil = onlineUntil
        self.lastSeen = lastSeen
        self.photos = photos
        self.height = height
        self.weight = weight
        self.position = position
        self.bodyType = bodyType
        self.ethnicity = ethnicity
        self.relationshipStatus = relationshipStatus
        self.tribes = tribes
        self.tribesImInto = tribesImInto
        self.lookingFor = lookingFor
        self.meetAt = meetAt
        self.acceptsNSFWPics = acceptsNSFWPics
        self.hivStatus = hivStatus
        self.lastTested = lastTested
        self.sexualHealth = sexualHealth
        self.vaccines = vaccines
        self.genderIDs = genderIDs
        self.pronounIDs = pronounIDs
        self.tags = tags
        self.instagram = instagram
        self.isFavorite = isFavorite
        self.receivedTap = receivedTap
        self.hasBeenTapped = hasBeenTapped
        self.isNew = isNew
        self.isVisiting = isVisiting
        self.isRoaming = isRoaming
        self.unreadCount = unreadCount
        self.showsTribes = showsTribes
        self.showsPosition = showsPosition
    }

    public var primaryPhoto: ProfilePhoto? { photos.first }

    public func isOnline(at date: Date = .now) -> Bool {
        onlineUntil.map { $0 > date } ?? false
    }

    /// The conversation id of a chat between this profile and `profileID`.
    public func conversationID(with profileID: ProfileID) -> String {
        Conversation.id(between: id, and: profileID)
    }
}

extension Profile: Decodable {
    enum CodingKeys: String, CodingKey {
        case profileId, displayName, aboutMe, age, showAge, distance, approximateDistance, showDistance
        case onlineUntil, seen, medias, profileImageMediaHash, height, weight, sexualPosition, bodyType
        case ethnicity, relationshipStatus, grindrTribes, tribesImInto, lookingFor, meetAt, nsfw,
            hivStatus
        case lastTestedDate, sexualHealth, vaccines, genders, pronouns, profileTags, socialNetworks,
            isFavorite
        case tapType, tapped, isNew, isVisiting, isRoaming, unreadCount, showTribes, showPosition
    }

    private struct Media: Decodable {
        var mediaHash: String
        var state: Int?
    }

    private struct SocialNetworks: Decodable {
        struct Account: Decodable { var userId: String? }
        var instagram: Account?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleInt(forKey: .profileId)
        displayName = container.lenient(String.self, forKey: .displayName)
        aboutMe = container.lenient(String.self, forKey: .aboutMe)
        age = container.lenient(Int.self, forKey: .age)
        showsAge = container.flag(forKey: .showAge)
        distance = container.lenient(Double.self, forKey: .distance)
        isDistanceApproximate = container.flag(forKey: .approximateDistance)
        showsDistance = container.flag(forKey: .showDistance)
        onlineUntil = container.timestamp(forKey: .onlineUntil)
        lastSeen = container.timestamp(forKey: .seen)

        var photos = container.lossyArray(of: Media.self, forKey: .medias).map {
            // State 0 means the photo is waiting for moderation.
            ProfilePhoto(mediaHash: $0.mediaHash, isPendingReview: $0.state == 0)
        }
        if let primary = container.lenient(String.self, forKey: .profileImageMediaHash),
            !photos.contains(where: { $0.mediaHash == primary })
        {
            photos.insert(ProfilePhoto(mediaHash: primary), at: 0)
        }
        self.photos = photos

        height = container.lenient(Double.self, forKey: .height)
        weight = container.lenient(Double.self, forKey: .weight)
        position = SexualPosition.known(container.lenient(Int.self, forKey: .sexualPosition))
        bodyType = BodyType.known(container.lenient(Int.self, forKey: .bodyType))
        ethnicity = Ethnicity.known(container.lenient(Int.self, forKey: .ethnicity))
        relationshipStatus = RelationshipStatus.known(
            container.lenient(Int.self, forKey: .relationshipStatus))
        tribes = Tribe.known(container.lenient([Int].self, forKey: .grindrTribes))
        tribesImInto = Tribe.known(container.lenient([Int].self, forKey: .tribesImInto))
        lookingFor = LookingFor.known(container.lenient([Int].self, forKey: .lookingFor))
        meetAt = MeetAt.known(container.lenient([Int].self, forKey: .meetAt))
        acceptsNSFWPics = AcceptsNSFWPics.known(container.lenient(Int.self, forKey: .nsfw))
        hivStatus = HIVStatus.known(container.lenient(Int.self, forKey: .hivStatus))
        lastTested = container.timestamp(forKey: .lastTestedDate)
        sexualHealth = SexualHealthPractice.known(container.lenient([Int].self, forKey: .sexualHealth))
        vaccines = Vaccine.known(container.lenient([Int].self, forKey: .vaccines))
        genderIDs = container.lenient([Int].self, forKey: .genders) ?? []
        pronounIDs = container.lenient([Int].self, forKey: .pronouns) ?? []
        tags = container.lenient([String].self, forKey: .profileTags) ?? []
        instagram = container.lenient(SocialNetworks.self, forKey: .socialNetworks)?.instagram?.userId
        isFavorite = container.flag(forKey: .isFavorite)
        receivedTap = TapType.known(container.lenient(Int.self, forKey: .tapType))
        hasBeenTapped = container.flag(forKey: .tapped)
        isNew = container.flag(forKey: .isNew)
        isVisiting = container.flag(forKey: .isVisiting)
        isRoaming = container.flag(forKey: .isRoaming)
        unreadCount = container.lenient(Int.self, forKey: .unreadCount) ?? 0
        // Missing means shown: the server leaves out default values.
        showsTribes = container.lenient(Bool.self, forKey: .showTribes) ?? true
        showsPosition = container.lenient(Bool.self, forKey: .showPosition) ?? true
    }

    /// Grindr answers a blocked or deleted profile with a stub whose display
    /// name is a magic digit and whose every other field is empty.
    var isUnavailableStub: Bool {
        guard displayName == "3" || displayName == "4" else { return false }
        return aboutMe == nil && age == nil && photos.isEmpty && distance == nil && onlineUntil == nil
            && tribes.isEmpty && lookingFor.isEmpty && lastSeen == nil
    }
}

/// A short profile, as `POST /v3/profiles` returns it for a batch of ids.
public struct ProfileSummary: Identifiable, Hashable, Sendable, Decodable {
    public var id: ProfileID
    public var displayName: String?
    public var age: Int?
    public var distance: Double?
    public var onlineUntil: Date?
    public var photoHash: String?
    public var isFavorite: Bool

    enum CodingKeys: String, CodingKey {
        case profileId, displayName, age, distance, onlineUntil, profileImageMediaHash, isFavorite
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleInt(forKey: .profileId)
        displayName = container.lenient(String.self, forKey: .displayName)
        age = container.lenient(Int.self, forKey: .age)
        distance = container.lenient(Double.self, forKey: .distance)
        onlineUntil = container.timestamp(forKey: .onlineUntil)
        photoHash = container.lenient(String.self, forKey: .profileImageMediaHash)
        isFavorite = container.flag(forKey: .isFavorite)
    }

    public init(
        id: ProfileID, displayName: String?, age: Int? = nil, distance: Double? = nil,
        onlineUntil: Date? = nil,
        photoHash: String? = nil, isFavorite: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.age = age
        self.distance = distance
        self.onlineUntil = onlineUntil
        self.photoHash = photoHash
        self.isFavorite = isFavorite
    }
}

/// A gender option from `GET /public/v2/genders`.
public struct Gender: Identifiable, Hashable, Sendable, Decodable {
    public var id: Int
    public var name: String
    public var pluralName: String?
    /// 0 for genders that can't be put on a profile; missing counts as offered.
    public var displayGroup: Int?
    /// Where the gender goes in the profile list.
    public var profileSortOrder: Int?
    /// Genders that can't be chosen together with this one.
    public var excludedOnProfile: [Int]

    enum CodingKeys: String, CodingKey {
        case genderId, gender, genderPlural, displayGroup, sortProfile, excludeOnProfileSelection
    }

    public init(
        id: Int, name: String, pluralName: String? = nil, displayGroup: Int? = nil, profileSortOrder: Int? = nil,
        excludedOnProfile: [Int] = []
    ) {
        self.id = id
        self.name = name
        self.pluralName = pluralName
        self.displayGroup = displayGroup
        self.profileSortOrder = profileSortOrder
        self.excludedOnProfile = excludedOnProfile
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .genderId)
        name = try container.decode(String.self, forKey: .gender)
        pluralName = container.lenient(String.self, forKey: .genderPlural)
        displayGroup = container.lenient(Int.self, forKey: .displayGroup)
        profileSortOrder = container.lenient(Int.self, forKey: .sortProfile)
        excludedOnProfile = container.lenient([Int].self, forKey: .excludeOnProfileSelection) ?? []
    }

    /// Whether the gender can be put on a profile.
    public var isOfferedOnProfile: Bool { (displayGroup ?? 1) > 0 }

    /// The genders you can choose from, in Grindr's order: the main genders
    /// first (as upstream Open Grind orders them), then by the catalog's order.
    public static func profileOptions(_ genders: [Gender]) -> [Gender] {
        let primary = [1, 4, 5, 2, 6, 7, 3]
        func rank(_ gender: Gender) -> (Int, Int, Int) {
            (primary.firstIndex(of: gender.id) ?? .max, gender.profileSortOrder ?? .max, gender.id)
        }
        return genders.filter(\.isOfferedOnProfile).sorted { rank($0) < rank($1) }
    }
}

/// A pronoun option from `GET /v1/pronouns`.
public struct Pronoun: Identifiable, Hashable, Sendable, Decodable {
    public var id: Int
    public var name: String

    enum CodingKeys: String, CodingKey {
        case pronounId, pronoun
    }

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .pronounId)
        name = try container.decode(String.self, forKey: .pronoun)
    }
}

/// A profile you blocked.
public struct BlockedProfile: Identifiable, Hashable, Sendable, Decodable {
    public var id: ProfileID
    public var blockedAt: Date?

    enum CodingKeys: String, CodingKey {
        case profileId, blockedTime
    }

    public init(id: ProfileID, blockedAt: Date? = nil) {
        self.id = id
        self.blockedAt = blockedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleInt(forKey: .profileId)
        blockedAt = container.timestamp(forKey: .blockedTime)
    }
}

/// The answer to a profile photo upload (`POST /v4/media/upload`).
struct UploadedProfilePhoto: Decodable {
    var photo: ProfilePhoto

    enum CodingKeys: String, CodingKey {
        case hash, imageSizes
    }

    private struct ImageSize: Decodable {
        var mediaHash: String?
        var state: String?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let size = container.lossyArray(of: ImageSize.self, forKey: .imageSizes).first
        guard let hash = size?.mediaHash ?? container.lenient(String.self, forKey: .hash), !hash.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .imageSizes, in: container, debugDescription: "The upload named no photo")
        }
        // New photos wait for moderation unless the server says otherwise.
        photo = ProfilePhoto(mediaHash: hash, isPendingReview: (size?.state ?? "Pending") == "Pending")
    }
}
