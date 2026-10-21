import OpenGrindKit
import SwiftUI

/// Where a navigation stack can go.
enum Route: Hashable {
    /// `fromChat`: opened from the chat with this profile, so "Message" goes back.
    case profile(ProfileID, fromChat: Bool = false)
    case chat(ProfileID)
}

/// The signed-in app: Browse, Messages, Interest and your profile.
struct MainTabView: View {
    enum Tab: String {
        case browse, messages, interest, me
    }

    @Environment(AccountSession.self) private var session
    @Environment(AppModel.self) private var app
    @SceneStorage("selectedTab") private var selection = Tab.browse

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Browse", systemImage: "square.grid.3x3.fill", value: Tab.browse) {
                BrowseView()
            }
            SwiftUI.Tab("Messages", systemImage: "bubble.left.and.bubble.right.fill", value: Tab.messages) {
                InboxView()
            }
            .badge(session.inbox.unreadCount)
            SwiftUI.Tab("Interest", systemImage: "heart.fill", value: Tab.interest) {
                InterestView()
            }
            .badge(session.interest.unseenCount)
            SwiftUI.Tab("Profile", systemImage: "person.crop.circle.fill", value: Tab.me) {
                MeView()
            }
        }
        .modifier(TabBarMinimizesOnScroll())
        .task {
            // Fill the badges right away; your profile has the gender and pronoun names.
            async let inbox: Void = session.inbox.loadIfNeeded()
            async let interest: Void = session.interest.loadIfNeeded()
            async let me: Void = session.me.loadIfNeeded()
            _ = await (inbox, interest, me)
        }
        .alert(
            "Your Account Is Restricted", isPresented: Bindable(app.account).restriction.isPresent(),
            presenting: app.account.restriction
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { restriction in
            Text(Self.explanation(of: restriction))
        }
    }

    private static func explanation(of restriction: AccountRestriction) -> String {
        switch restriction {
        case .ageVerification(let region):
            String(
                localized:
                    "Grindr requires age verification in \(region). Verify your age in the Grindr app.")
        case .temporaryBan(let until, let reason):
            [
                until.map {
                    String(
                        localized:
                            "Grindr suspended this account until \($0.formatted(date: .abbreviated, time: .shortened))."
                    )
                } ?? String(localized: "Grindr suspended this account for now."),
                reason,
            ].compactMap(\.self).joined(separator: " ")
        case .rejectedByTrustVendor:
            String(localized: "Grindr's safety checks flagged this account. Contact Grindr support.")
        case .other(let detail):
            String(localized: "Grindr limited this account: \(detail)")
        }
    }
}

/// On iOS 26, the tab bar gets out of the way while scrolling, as in Apple's apps.
private struct TabBarMinimizesOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

extension View {
    /// The destinations every tab can push.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .profile(let id, let fromChat): ProfileScreen(profileID: id, isFromChat: fromChat)
            case .chat(let id): ChatScreen(profileID: id)
            }
        }
    }
}
