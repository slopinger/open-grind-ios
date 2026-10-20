import Foundation
import OpenGrindKit

/// What to tell the user about a ``Failure``.
struct FailureText {
    var title: String
    var message: String
    var systemImage: String

    init(_ failure: Failure) {
        switch failure {
        case .location(.denied):
            title = String(localized: "Location Access Needed")
            message = String(
                localized:
                    "Open Grind uses your location to find people nearby. Allow location access in Settings.")
            systemImage = "location.slash"
        case .location(.restricted):
            title = String(localized: "Location Restricted")
            message = String(localized: "Location access is restricted on this device.")
            systemImage = "location.slash"
        case .location(.unavailable):
            title = String(localized: "Location Unavailable")
            message = String(localized: "Your location couldn't be determined. Try again in a moment.")
            systemImage = "location.slash"
        case .grindr(let error):
            let described = Self.describe(error)
            title = described.0
            message = described.1
            systemImage = described.2
        case .unexpected:
            title = String(localized: "Something Went Wrong")
            message = String(localized: "Please try again.")
            systemImage = "exclamationmark.triangle"
        }
    }

    /// Whether the failure is fixed in the Settings app.
    static func needsSettings(_ failure: Failure) -> Bool {
        failure == .location(.denied)
    }

    private static func describe(_ error: GrindrError) -> (String, String, String) {
        switch error {
        case .offline:
            (
                String(localized: "No Connection"),
                String(localized: "Check your internet connection and try again."),
                "wifi.slash"
            )
        case .timedOut:
            (
                String(localized: "Grindr Isn't Responding"),
                String(localized: "The request took too long. Try again."),
                "clock.badge.exclamationmark"
            )
        case .notSignedIn, .unauthorized:
            (
                String(localized: "Signed Out"), String(localized: "Sign in again to continue."),
                "person.crop.circle.badge.exclamationmark"
            )
        case .banned(let scope, _):
            (
                String(localized: "Account Banned"),
                scope == .underage
                    ? String(
                        localized: "Grindr banned this account because it may belong to someone under 18.")
                    : String(localized: "Grindr banned this account. Contact Grindr support to appeal."),
                "hand.raised"
            )
        case .rateLimited:
            (
                String(localized: "Slow Down"),
                String(localized: "Grindr is limiting requests. Wait a minute and try again."),
                "hourglass"
            )
        case .blocked:
            (
                String(localized: "Grindr Blocked the Request"),
                String(
                    localized:
                        "Grindr's network protection stopped this request. It usually works again after a short wait."
                ),
                "shield.lefthalf.filled.slash"
            )
        case .unavailable:
            (
                String(localized: "Not Available"),
                String(localized: "This profile or conversation is no longer available."),
                "person.crop.circle.badge.xmark"
            )
        case .requiresSubscription:
            (
                String(localized: "Subscription Required"),
                String(localized: "Grindr only offers this with a paid subscription."), "lock"
            )
        case .rejectedText:
            (
                String(localized: "Text Not Allowed"),
                String(
                    localized:
                        "Grindr didn't accept some of the words in your profile. Change them and try again."),
                "text.badge.xmark"
            )
        case .mediaTooLarge:
            (
                String(localized: "File Too Large"), String(localized: "Choose a smaller photo."),
                "photo.badge.exclamationmark"
            )
        case .server(let status, _, _) where status >= 500:
            (
                String(localized: "Grindr Is Having Problems"),
                String(localized: "Try again in a few minutes."),
                "exclamationmark.icloud"
            )
        case .server, .invalidResponse, .invalidRequest, .cancelled, .internal:
            (
                String(localized: "Something Went Wrong"),
                String(localized: "Grindr didn't accept the request. Try again."),
                "exclamationmark.triangle"
            )
        }
    }
}
