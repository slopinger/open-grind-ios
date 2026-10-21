import Foundation

/// The parts of your own profile you can edit. Saving sends the whole profile
/// (`PUT /v3.1/me/profile`), as Grindr's own Edit Profile screen does.
public struct ProfileEdit: Hashable, Sendable {
    public static let maxDisplayNameLength = 15
    public static let maxAboutMeLength = 255
    public static let ageRange = BrowseFilters.ageBounds
    public static let maxTags = 10
    public static let maxGenders = 3
    public static let maxPronouns = 3

    public var displayName: String
    public var aboutMe: String
    public var age: Int?
    public var showsAge: Bool
    public var showsDistance: Bool
    /// Centimeters.
    public var height: Double?
    /// Grams.
    public var weight: Double?
    public var position: SexualPosition?
    public var showsPosition: Bool
    public var bodyType: BodyType?
    public var ethnicity: Ethnicity?
    public var relationshipStatus: RelationshipStatus?
    public var lookingFor: Set<LookingFor>
    public var meetAt: Set<MeetAt>
    public var tribes: Set<Tribe>
    public var showsTribes: Bool
    public var acceptsNSFWPics: AcceptsNSFWPics?
    public var hivStatus: HIVStatus?
    public var lastTested: Date?
    public var sexualHealth: Set<SexualHealthPractice>
    public var vaccines: Set<Vaccine>
    /// In the order they were chosen.
    public var genderIDs: [Int]
    public var pronounIDs: [Int]
    /// Catalog keys, as ``MeModel`` keeps your profile's tags.
    public var tags: Set<String>

    public init(_ profile: Profile) {
        displayName = profile.displayName ?? ""
        aboutMe = profile.aboutMe ?? ""
        age = profile.age
        showsAge = profile.showsAge
        showsDistance = profile.showsDistance
        height = profile.height
        weight = profile.weight
        position = profile.position
        showsPosition = profile.showsPosition
        bodyType = profile.bodyType
        ethnicity = profile.ethnicity
        relationshipStatus = profile.relationshipStatus
        lookingFor = Set(profile.lookingFor)
        meetAt = Set(profile.meetAt)
        tribes = Set(profile.tribes)
        showsTribes = profile.showsTribes
        acceptsNSFWPics = profile.acceptsNSFWPics
        // "Prefer to discuss" can be shown but not set.
        hivStatus = profile.hivStatus == .preferToDiscuss ? nil : profile.hivStatus
        lastTested = profile.lastTested
        sexualHealth = Set(profile.sexualHealth).intersection(SexualHealthPractice.settableCases)
        vaccines = Set(profile.vaccines)
        genderIDs = profile.genderIDs
        pronounIDs = profile.pronounIDs
        tags = Set(profile.tags)
    }

    /// Whether the edit can be saved.
    public var isValid: Bool {
        displayName.count <= Self.maxDisplayNameLength && aboutMe.count <= Self.maxAboutMeLength
            && age.map(Self.ageRange.contains) ?? true && tags.count <= Self.maxTags
            && genderIDs.count <= Self.maxGenders && pronounIDs.count <= Self.maxPronouns
    }

    /// The `PUT /v3.1/me/profile` body: `profile` with this edit applied, with the
    /// fields Grindr's Edit Profile screen sends, or `nil` if nothing changed.
    /// Fields the form doesn't show (tribes you're into, social networks,
    /// approximate distance) keep the profile's values.
    public func update(of profile: Profile) -> JSONValue? {
        guard self != ProfileEdit(profile) else { return nil }
        let saved = applied(to: profile)
        func list<T: ProfileAttribute>(_ values: [T]) -> JSONValue { .ints(values.map(\.rawValue)) }
        func one<T: ProfileAttribute>(_ value: T?) -> JSONValue { .optional(value?.rawValue) }
        return .object([
            "displayName": .optional(saved.displayName),
            "aboutMe": .optional(saved.aboutMe),
            "age": .optional(saved.age),
            "showAge": .bool(saved.showsAge),
            "showDistance": .bool(saved.showsDistance),
            "approximateDistance": .bool(saved.isDistanceApproximate),
            "height": .optional(saved.height),
            "weight": .optional(saved.weight),
            "sexualPosition": one(saved.position),
            "showPosition": .bool(saved.showsPosition),
            "bodyType": one(saved.bodyType),
            "ethnicity": one(saved.ethnicity),
            "relationshipStatus": one(saved.relationshipStatus),
            "lookingFor": list(saved.lookingFor),
            "meetAt": list(saved.meetAt),
            "grindrTribes": list(saved.tribes),
            "tribesImInto": list(saved.tribesImInto),
            "showTribes": .bool(saved.showsTribes),
            "nsfw": one(saved.acceptsNSFWPics),
            "hivStatus": one(saved.hivStatus),
            "lastTestedDate": .timestamp(saved.lastTested),
            "sexualHealth": list(saved.sexualHealth),
            "vaccines": list(saved.vaccines),
            "genders": .ints(saved.genderIDs),
            "pronouns": .ints(saved.pronounIDs),
            "profileTags": .strings(saved.tags),
            "socialNetworks": .object(saved.socialNetworks.mapValues { .object(["userId": .string($0)]) }),
        ])
    }

    /// `profile` with this edit applied, to show the change before the server
    /// sends the profile again. Values the form can't show, such as "prefer to
    /// discuss", stay unless they were changed.
    public func applied(to profile: Profile) -> Profile {
        let original = ProfileEdit(profile)
        var profile = profile
        profile.displayName = displayName.nonBlank
        profile.aboutMe = aboutMe.nonBlank
        profile.age = age
        profile.showsAge = showsAge
        profile.showsDistance = showsDistance
        profile.height = height
        profile.weight = weight
        profile.position = position
        profile.showsPosition = showsPosition
        profile.bodyType = bodyType
        profile.ethnicity = ethnicity
        profile.relationshipStatus = relationshipStatus
        profile.lookingFor = LookingFor.allCases.filter(lookingFor.contains)
        profile.meetAt = MeetAt.allCases.filter(meetAt.contains)
        profile.tribes = Tribe.allCases.filter(tribes.contains)
        profile.showsTribes = showsTribes
        profile.acceptsNSFWPics = acceptsNSFWPics
        if hivStatus != original.hivStatus { profile.hivStatus = hivStatus }
        profile.lastTested = lastTested
        if sexualHealth != original.sexualHealth {
            profile.sexualHealth = SexualHealthPractice.allCases.filter(sexualHealth.contains)
        }
        profile.vaccines = Vaccine.allCases.filter(vaccines.contains)
        profile.genderIDs = genderIDs
        profile.pronounIDs = pronounIDs
        profile.tags = tags.sorted()
        return profile
    }
}
