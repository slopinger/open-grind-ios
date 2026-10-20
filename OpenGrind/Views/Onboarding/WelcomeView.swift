import OpenGrindKit
import SwiftUI

/// The first screen: what Open Grind is, sign in, or try the demo.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    if let reason = model.account.signedOutReason {
                        SignedOutNotice(reason: reason)
                    }
                    features
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                actions
            }
            .sheet(isPresented: $isSigningIn) {
                SignInView()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(.logo)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.brand)
                .padding(14)
                .frame(width: 96, height: 96)
                .background(
                    LinearGradient(
                        colors: [Color(white: 0.23), Color(white: 0.04)], startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 22, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Open Grind")
                    .font(.largeTitle.bold())
                Text("A free, private client for Grindr.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 20) {
            Feature(
                systemImage: "eye.slash", title: "No Ads, No Trackers",
                text: "Open Grind talks only to Grindr. Nothing about you is sent anywhere else.")
            Feature(
                systemImage: "location.circle", title: "Approximate Location",
                text: "Your position is rounded to about 100 meters before it leaves your iPhone.")
            Feature(
                systemImage: "chevron.left.forwardslash.chevron.right", title: "Open Source",
                text: "Built on the Open Grind project. Anyone can read and check the code.")
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                isSigningIn = true
            } label: {
                Text("Sign In with Email")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandProminent)
            .controlSize(.large)

            Button {
                model.startDemo()
            } label: {
                Text("Try the Demo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text(
                "Open Grind is not affiliated with or endorsed by Grindr. Using an unofficial client may break Grindr's terms of service."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

private struct Feature: View {
    let systemImage: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Why the account was signed out, when the server did it.
private struct SignedOutNotice: View {
    let reason: SignedOutReason

    var body: some View {
        Label {
            switch reason {
            case .sessionExpired:
                Text("Your session ended. Sign in again to continue.")
            case .banned(let detail):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grindr banned this account.")
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
    }
}
