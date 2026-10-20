import Foundation
import OpenGrindKit
import Testing

@testable import OpenGrind

struct FormattingTests {
    @Test func distancesAreRoundedAndMarkedWhenApproximate() {
        #expect(Formatting.distance(nil) == nil)
        #expect(Formatting.distance(-1) == nil)
        #expect(Formatting.distance(40) == String(localized: "Nearby"))
        #expect(Formatting.distance(1500, approximate: true)?.hasPrefix("~") == true)
    }

    @Test func presenceSaysOnlineOnlyWhileOnline() {
        let now = Date.now
        #expect(Formatting.presence(onlineUntil: now.addingTimeInterval(60), lastSeen: nil, now: now) != nil)
        #expect(Formatting.presence(onlineUntil: now.addingTimeInterval(-60), lastSeen: nil, now: now) == nil)
    }

    @Test func everyFailureHasText() {
        let errors: [GrindrError] = [
            .offline, .timedOut, .notSignedIn, .unauthorized, .banned(.underage, reason: nil), .rateLimited,
            .blocked, .server(status: 503, code: nil, message: nil), .unavailable, .requiresSubscription,
            .rejectedText, .invalidResponse("x"), .mediaTooLarge, .cancelled,
        ]
        for failure in errors.map(Failure.grindr) + [.location(.denied), .location(.unavailable), .unexpected("x")] {
            let text = FailureText(failure)
            #expect(!text.title.isEmpty)
            #expect(!text.message.isEmpty)
        }
        #expect(FailureText.needsSettings(.location(.denied)))
        #expect(!FailureText.needsSettings(.grindr(.offline)))
    }

    @Test func messagePreviewsDescribeMedia() {
        #expect(MessageText.preview(kind: .text, text: "Hi", isUnsent: false) == "Hi")
        #expect(MessageText.preview(kind: .text, text: "Hi", isUnsent: true) != "Hi")
        #expect(MessageText.preview(kind: .image, text: nil, isUnsent: false).contains("📷"))
    }
}
