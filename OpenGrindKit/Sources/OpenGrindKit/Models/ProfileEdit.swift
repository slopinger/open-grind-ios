import Foundation

/// The parts of your own profile you can edit. Saving sends only what changed
/// (`PATCH /v4/me/profile`).
public struct ProfileEdit: Hashable, Sendable {
    public static let maxDisplayNameLength = 15
    public static let maxAboutMeLength = 255
    public static let ageRange = 18...99
    public static let maxTags = 10

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
    /// Sent by key; the text is what your profile shows.
    public var tags: Set<ProfileTag>

    /// - Parameter tagCatalog: matches your tags to catalog keys; without it, a tag's
    ///   key is the text the profile carries.
    public init(_ profile: Profile, tagCatalog: ProfileTagCatalog? = nil) {
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
        tags = Set(profile.tags.map { tagCatalog?.tag(matching: $0) ?? ProfileTag(key: $0, text: $0) })
    }

    /// Whether the edit can be saved.
    public var isValid: Bool {
        displayName.count <= Self.maxDisplayNameLength && aboutMe.count <= Self.maxAboutMeLength
            && age.map(Self.ageRange.contains) ?? true && tags.count <= Self.maxTags
    }

    /// The `PATCH` body with the fields that differ from `original`, or `nil`
    /// if nothing changed.
    public func patch(from original: ProfileEdit) -> JSONValue? {
        var fields: [String: JSONValue] = [:]
        func text(_ value: String) -> JSONValue {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .null : .string(trimmed)
        }
        func set<T: ProfileAttribute>(_ values: Set<T>) -> JSONValue {
            .ints(values.map(\.rawValue).sorted())
        }
        func one<T: ProfileAttribute>(_ value: T?) -> JSONValue { .optional(value?.rawValue) }

        if displayName != original.displayName { fields["displayName"] = text(displayName) }
        if aboutMe != original.aboutMe { fields["aboutMe"] = text(aboutMe) }
        if age != original.age { fields["age"] = .optional(age) }
        if showsAge != original.showsAge { fields["showAge"] = .bool(showsAge) }
        if showsDistance != original.showsDistance { fields["showDistance"] = .bool(showsDistance) }
        if height != original.height { fields["height"] = .optional(height) }
        if weight != original.weight { fields["weight"] = .optional(weight) }
        if position != original.position { fields["sexualPosition"] = one(position) }
        if showsPosition != original.showsPosition { fields["showPosition"] = .bool(showsPosition) }
        if bodyType != original.bodyType { fields["bodyType"] = one(bodyType) }
        if ethnicity != original.ethnicity { fields["ethnicity"] = one(ethnicity) }
        if relationshipStatus != original.relationshipStatus {
            fields["relationshipStatus"] = one(relationshipStatus)
        }
        if lookingFor != original.lookingFor { fields["lookingFor"] = set(lookingFor) }
        if meetAt != original.meetAt { fields["meetAt"] = set(meetAt) }
        if tribes != original.tribes { fields["grindrTribes"] = set(tribes) }
        if showsTribes != original.showsTribes { fields["showTribes"] = .bool(showsTribes) }
        if acceptsNSFWPics != original.acceptsNSFWPics { fields["nsfw"] = one(acceptsNSFWPics) }
        if hivStatus != original.hivStatus { fields["hivStatus"] = one(hivStatus) }
        if lastTested != original.lastTested {
            fields["lastTestedDate"] = lastTested.map { .number(Double($0.milliseconds)) } ?? .null
        }
        if sexualHealth != original.sexualHealth { fields["sexualHealth"] = set(sexualHealth) }
        if vaccines != original.vaccines { fields["vaccines"] = set(vaccines) }
        if Set(tags.map(\.key)) != Set(original.tags.map(\.key)) {
            fields["profileTags"] = .array(tags.map(\.key).sorted().map(JSONValue.string))
        }
        return fields.isEmpty ? nil : .object(fields)
    }

    /// `profile` with this edit applied, to show the change before the server
    /// sends the profile again.
    public func applied(to profile: Profile) -> Profile {
        var profile = profile
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let about = aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.displayName = name.isEmpty ? nil : name
        profile.aboutMe = about.isEmpty ? nil : about
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
        profile.hivStatus = hivStatus
        profile.lastTested = lastTested
        profile.sexualHealth = SexualHealthPractice.allCases.filter(sexualHealth.contains)
        profile.vaccines = Vaccine.allCases.filter(vaccines.contains)
        profile.tags = tags.map(\.text).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return profile
    }
}
