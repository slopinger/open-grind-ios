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
            self = Self.describe(error)
        case .unexpected:
            title = String(localized: "Something Went Wrong")
            message = String(localized: "Please try again.")
            systemImage = "exclamationmark.triangle"
        }
    }

    private init(_ title: String, _ message: String, _ systemImage: String) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    /// Whether the failure is fixed in the Settings app.
    static func needsSettings(_ failure: Failure) -> Bool {
        failure == .location(.denied)
    }

    /// Whether trying the same thing again could work.
    static func canRetry(_ failure: Failure) -> Bool {
        switch failure {
        case .grindr(.requiresSubscription), .grindr(.rejectedText), .grindr(.banned), .location(.restricted): false
        default: true
        }
    }

    private static func describe(_ error: GrindrError) -> FailureText {
        switch error {
        case .offline:
            FailureText(
                String(localized: "No Connection"),
                String(localized: "Check your internet connection and try again."),
                "wifi.slash"
            )
        case .timedOut:
            FailureText(
                String(localized: "Grindr Isn't Responding"),
                String(localized: "The request took too long. Try again."),
                "clock.badge.exclamationmark"
            )
        case .notSignedIn, .unauthorized:
            FailureText(
                String(localized: "Signed Out"), String(localized: "Sign in again to continue."),
                "person.crop.circle.badge.exclamationmark"
            )
        case .banned(let scope, _):
            FailureText(
                String(localized: "Account Banned"),
                scope == .underage
                    ? String(
                        localized: "Grindr banned this account because it may belong to someone under 18.")
                    : String(localized: "Grindr banned this account. Contact Grindr support to appeal."),
                "hand.raised"
            )
        case .rateLimited:
            FailureText(
                String(localized: "Slow Down"),
                String(localized: "Grindr is limiting requests. Wait a minute and try again."),
                "hourglass"
            )
        case .blocked:
            FailureText(
                String(localized: "Grindr Blocked the Request"),
                String(
                    localized:
                        "Grindr's network protection stopped this request. It usually works again after a short wait."
                ),
                "shield.lefthalf.filled.slash"
            )
        case .unavailable:
            FailureText(
                String(localized: "Not Available"),
                String(localized: "This profile or conversation is no longer available."),
                "person.crop.circle.badge.xmark"
            )
        case .requiresSubscription:
            FailureText(
                String(localized: "Subscription Required"),
                String(localized: "Grindr only offers this with a paid subscription."), "lock"
            )
        case .rejectedText:
            FailureText(
                String(localized: "Text Not Allowed"),
                String(
                    localized:
                        "Grindr didn't accept some of the words in your profile. Change them and try again."),
                "text.badge.xmark"
            )
        case .mediaTooLarge:
            FailureText(
                String(localized: "File Too Large"), String(localized: "Choose a smaller photo."),
                "photo.badge.exclamationmark"
            )
        case .server(let status, _, _) where status >= 500:
            FailureText(
                String(localized: "Grindr Is Having Problems"),
                String(localized: "Try again in a few minutes."),
                "exclamationmark.icloud"
            )
        case .server, .invalidResponse, .invalidRequest, .cancelled, .internal:
            FailureText(
                String(localized: "Something Went Wrong"),
                String(localized: "Grindr didn't accept the request. Try again."),
                "exclamationmark.triangle"
            )
        }
    }
}
