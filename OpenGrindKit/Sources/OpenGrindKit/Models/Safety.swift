import Foundation

/// Why a profile is reported (`POST /v3.1/flags/{id}`).
public enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam = "SPAM"
    case harassment = "HARASSMENT_BULLYING"
    case hate = "HATE_DISCRIMINATION"
    case nudity = "NUDITY_PORNOGRAPHY"
    case underage = "UNDERAGE"
    case impersonation = "IMPERSONATION"
    case illegalActivity = "ILLEGAL_ACTIVITY"
    case solicitation = "SEXUAL_SOLICITATION"
    case inPersonIncident = "SERIOUS_IN_PERSON_INCIDENT"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment or bullying"
        case .hate: "Hate or discrimination"
        case .nudity: "Nudity or pornography"
        case .underage: "Underage"
        case .impersonation: "Impersonation"
        case .illegalActivity: "Illegal activity"
        case .solicitation: "Sexual solicitation"
        case .inPersonIncident: "Serious in-person incident"
        }
    }
}

/// Where the reported content is.
public enum ReportLocation: String, CaseIterable, Identifiable, Sendable {
    case profilePhoto = "PROFILE_PHOTO"
    case profileInformation = "PROFILE_INFORMATION"
    case chatMessage = "CHAT_MESSAGE"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .profilePhoto: "Profile photo"
        case .profileInformation: "Profile information"
        case .chatMessage: "Chat messages"
        }
    }
}

/// A report about a profile.
public struct ProfileReport: Hashable, Sendable {
    public var reason: ReportReason
    public var locations: Set<ReportLocation>
    public var comment: String

    public init(reason: ReportReason, locations: Set<ReportLocation>, comment: String = "") {
        self.reason = reason
        self.locations = locations
        self.comment = comment
    }

    var requestBody: JSONValue {
        .object([
            "reason": .string(reason.rawValue),
            "comment": .string(comment),
            "locations": .strings(locations.map(\.rawValue).sorted()),
        ])
    }
}
