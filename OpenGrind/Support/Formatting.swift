import Foundation
import OpenGrindKit

/// Text for distances, sizes and times, in the user's locale and units.
enum Formatting {
    /// A profile's name, or "No name" for profiles without one.
    static func name(_ displayName: String?) -> String {
        guard let displayName, !displayName.isEmpty else { return String(localized: "No name") }
        return displayName
    }

    /// A place's name, or "Selected Place" while Apple Maps hasn't named it.
    static func place(_ name: String?) -> String {
        name ?? String(localized: "Selected Place")
    }

    /// "350 m" / "1.2 km" (or feet and miles), "Nearby" under 100 m, "~" when approximate.
    static func distance(_ meters: Double?, approximate: Bool = false) -> String? {
        guard let meters, meters >= 0 else { return nil }
        if meters < 100 { return String(localized: "Nearby", comment: "Distance under 100 meters") }
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let usesMetric = Locale.current.measurementSystem == .metric
        let rounded: Measurement<UnitLength> =
            if usesMetric {
                meters < 1000
                    ? Measurement(value: (meters / 10).rounded() * 10, unit: .meters)
                    : measurement.converted(to: .kilometers)
            } else {
                measurement.converted(to: .miles).value < 0.2
                    ? Measurement(
                        value: (measurement.converted(to: .feet).value / 50).rounded() * 50, unit: .feet)
                    : measurement.converted(to: .miles)
            }
        let text = rounded.formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0...1))))
        return approximate ? "~\(text)" : text
    }

    /// Height from centimeters, e.g. "180 cm" or "5′ 11″".
    static func height(_ centimeters: Double) -> String {
        let measurement = Measurement(value: centimeters, unit: UnitLength.centimeters)
        if Locale.current.measurementSystem == .metric {
            return measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
        let totalInches = Int(measurement.converted(to: .inches).value.rounded())
        return "\(totalInches / 12)′ \(totalInches % 12)″"
    }

    /// Weight from grams, e.g. "75 kg" or "165 lb".
    static func weight(_ grams: Double) -> String {
        let measurement = Measurement(value: grams, unit: UnitMass.grams)
        let unit: UnitMass = Locale.current.measurementSystem == .metric ? .kilograms : .pounds
        return Measurement(value: measurement.converted(to: unit).value.rounded(), unit: unit)
            .formatted(
                .measurement(width: .abbreviated, usage: .asProvided))
    }

    /// "Online now", "Active 5 min. ago", or nothing when unknown.
    static func presence(_ presence: some OnlinePresence, lastSeen: Date?, now: Date = .now) -> String? {
        if presence.isOnline(at: now) {
            return String(localized: "Online now")
        }
        guard let lastSeen, lastSeen < now else { return nil }
        if now.timeIntervalSince(lastSeen) < 60 {
            return String(localized: "Active just now")
        }
        let relative = lastSeen.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return String(localized: "Active \(relative)", comment: "e.g. Active 5 min. ago")
    }

    /// A compact time for lists: "14:05" today, "Yesterday", the weekday this
    /// week, the date before that.
    static func listTime(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }

    /// A header between days of a conversation.
    static func daySeparator(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

extension ProfileAttribute {
    /// The label in the user's language. Labels are keys in the string catalog.
    var localizedName: String {
        String(localized: String.LocalizationValue(displayName))
    }
}

extension TapType {
    /// A symbol rather than the official app's emoji, so it takes the text's
    /// weight and color.
    var systemImage: String {
        switch self {
        case .friendly: "hand.wave.fill"
        case .hot: "flame.fill"
        case .looking: "eyes"
        }
    }
}

extension ReportReason {
    var localizedName: String { String(localized: String.LocalizationValue(displayName)) }
}

extension ReportLocation {
    var localizedName: String { String(localized: String.LocalizationValue(displayName)) }
}

extension Sequence where Element: ProfileAttribute {
    /// "Chat, Dates and Friends", in the user's language.
    var localizedList: String {
        map(\.localizedName).formatted(.list(type: .and))
    }
}
