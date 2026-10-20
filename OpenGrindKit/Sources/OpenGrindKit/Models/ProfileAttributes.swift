import Foundation

/// A fixed-choice profile field the API sends as an integer id.
///
/// `displayName` is the English label Grindr uses. The app looks it up in its
/// string catalog, so the labels are also the localization keys.
public protocol ProfileAttribute: RawRepresentable, CaseIterable, Hashable, Sendable, Identifiable,
    Codable
where RawValue == Int, AllCases: RandomAccessCollection {
    var displayName: String { get }
}

extension ProfileAttribute {
    public var id: Int { rawValue }

    /// The known values among `ids`, dropping ids this version does not know.
    static func known(_ ids: [Int]?) -> [Self] {
        (ids ?? []).compactMap(Self.init(rawValue:))
    }

    static func known(_ id: Int?) -> Self? {
        id.flatMap(Self.init(rawValue:))
    }
}

public enum SexualPosition: Int, ProfileAttribute {
    case top = 1
    case bottom = 2
    case versatile = 3
    case versBottom = 4
    case versTop = 5
    case side = 6

    /// The order the official app lists positions in.
    public static let allCases: [SexualPosition] = [
        .top, .versTop, .versatile, .versBottom, .bottom, .side,
    ]

    public var displayName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .versatile: "Versatile"
        case .versBottom: "Vers Bottom"
        case .versTop: "Vers Top"
        case .side: "Side"
        }
    }
}

public enum LookingFor: Int, ProfileAttribute {
    case chat = 2
    case dates = 3
    case friends = 4
    case networking = 5
    case relationship = 6
    case hookups = 7

    public var displayName: String {
        switch self {
        case .chat: "Chat"
        case .dates: "Dates"
        case .friends: "Friends"
        case .networking: "Networking"
        case .relationship: "Relationship"
        case .hookups: "Hookups"
        }
    }
}

public enum AcceptsNSFWPics: Int, ProfileAttribute {
    case never = 1
    case notAtFirst = 2
    case yesPlease = 3

    public var displayName: String {
        switch self {
        case .never: "Never"
        case .notAtFirst: "Not At First"
        case .yesPlease: "Yes Please"
        }
    }
}

public enum RelationshipStatus: Int, ProfileAttribute {
    case single = 1
    case dating = 2
    case exclusive = 3
    case committed = 4
    case partnered = 5
    case engaged = 6
    case married = 7
    case openRelationship = 8

    public var displayName: String {
        switch self {
        case .single: "Single"
        case .dating: "Dating"
        case .exclusive: "Exclusive"
        case .committed: "Committed"
        case .partnered: "Partnered"
        case .engaged: "Engaged"
        case .married: "Married"
        case .openRelationship: "Open Relationship"
        }
    }
}

public enum BodyType: Int, ProfileAttribute {
    case toned = 1
    case average = 2
    case large = 3
    case muscular = 4
    case slim = 5
    case stocky = 6

    public var displayName: String {
        switch self {
        case .toned: "Toned"
        case .average: "Average"
        case .large: "Large"
        case .muscular: "Muscular"
        case .slim: "Slim"
        case .stocky: "Stocky"
        }
    }
}

public enum Tribe: Int, ProfileAttribute {
    case bear = 1
    case cleanCut = 2
    case daddy = 3
    case discreet = 4
    case geek = 5
    case jock = 6
    case leather = 7
    case otter = 8
    case poz = 9
    case rugged = 10
    case trans = 11
    case twink = 12
    case sober = 13

    public var displayName: String {
        switch self {
        case .bear: "Bear"
        case .cleanCut: "Clean-Cut"
        case .daddy: "Daddy"
        case .discreet: "Discreet"
        case .geek: "Geek"
        case .jock: "Jock"
        case .leather: "Leather"
        case .otter: "Otter"
        case .poz: "Poz"
        case .rugged: "Rugged"
        case .trans: "Trans"
        case .twink: "Twink"
        case .sober: "Sober"
        }
    }
}

public enum MeetAt: Int, ProfileAttribute {
    case myPlace = 1
    case yourPlace = 2
    case bar = 3
    case coffeeShop = 4
    case restaurant = 5

    public var displayName: String {
        switch self {
        case .myPlace: "My Place"
        case .yourPlace: "Your Place"
        case .bar: "Bar"
        case .coffeeShop: "Coffee Shop"
        case .restaurant: "Restaurant"
        }
    }
}

public enum Ethnicity: Int, ProfileAttribute {
    case asian = 1
    case black = 2
    case latino = 3
    case middleEastern = 4
    case mixed = 5
    case nativeAmerican = 6
    case white = 7
    case other = 8
    case southAsian = 9

    public var displayName: String {
        switch self {
        case .asian: "Asian"
        case .black: "Black"
        case .latino: "Latino"
        case .middleEastern: "Middle Eastern"
        case .mixed: "Mixed"
        case .nativeAmerican: "Native American"
        case .white: "White"
        case .other: "Other"
        case .southAsian: "South Asian"
        }
    }
}

public enum HIVStatus: Int, ProfileAttribute {
    case negative = 1
    case negativeOnPrEP = 2
    case positive = 3
    case positiveUndetectable = 4
    /// Shown on other profiles, but not offered when editing your own.
    case preferToDiscuss = 5

    public static let settableCases: [HIVStatus] = [
        .negative, .negativeOnPrEP, .positive, .positiveUndetectable,
    ]

    public var displayName: String {
        switch self {
        case .negative: "Negative"
        case .negativeOnPrEP: "Negative, on PrEP"
        case .positive: "Positive"
        case .positiveUndetectable: "Positive, undetectable"
        case .preferToDiscuss: "Prefer to discuss"
        }
    }
}

public enum SexualHealthPractice: Int, ProfileAttribute {
    case condoms = 1
    case doxyPEP = 2
    case prep = 3
    case hivUndetectable = 4
    case preferToDiscuss = 5
    /// Shown on other profiles, but not offered when editing your own.
    case sober = 6
    /// Shown on other profiles, but not offered when editing your own.
    case drugFree = 7

    public static let settableCases: [SexualHealthPractice] = [
        .condoms, .doxyPEP, .prep, .hivUndetectable, .preferToDiscuss,
    ]

    public var displayName: String {
        switch self {
        case .condoms: "Condoms"
        case .doxyPEP: "I'm on doxyPEP"
        case .prep: "I'm on PrEP"
        case .hivUndetectable: "I'm HIV undetectable"
        case .preferToDiscuss: "Prefer to discuss"
        case .sober: "Sober"
        case .drugFree: "Drug-Free"
        }
    }
}

public enum Vaccine: Int, ProfileAttribute {
    case covid19 = 1
    case monkeypox = 2
    case meningitis = 3

    public var displayName: String {
        switch self {
        case .covid19: "COVID-19"
        case .monkeypox: "Monkeypox"
        case .meningitis: "Meningitis"
        }
    }
}

/// The three kinds of tap. The API uses `3` for "no tap", which decodes as `nil`.
public enum TapType: Int, ProfileAttribute {
    case friendly = 0
    case hot = 1
    case looking = 2

    public var displayName: String {
        switch self {
        case .friendly: "Friendly"
        case .hot: "Hot"
        case .looking: "Looking"
        }
    }

    /// The emoji the official app shows for the tap.
    public var emoji: String {
        switch self {
        case .friendly: "🍪"
        case .hot: "🔥"
        case .looking: "😈"
        }
    }
}
