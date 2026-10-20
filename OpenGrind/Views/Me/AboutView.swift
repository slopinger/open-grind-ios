import OpenGrindCoreTransport
import OpenGrindKit
import SwiftUI

/// Version, credits and links.
struct AboutView: View {
    @Environment(AccountSession.self) private var session

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(.logo)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.brand)
                        .padding(10)
                        .frame(width: 64, height: 64)
                        .background(.black, in: .rect(cornerRadius: 15, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Open Grind")
                        .font(.title2.bold())
                    Text("Version \(appVersion)")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Grindr Protocol", value: CoreTransport.grindrVersion)
                LabeledContent("Live Updates") {
                    Text(session.isRealtimeConnected ? "Connected" : "Not Connected")
                }
            } footer: {
                Text("Open Grind talks to Grindr like the official Android app of this version.")
            }

            Section {
                Link(destination: URL(string: "https://github.com/slopinger/open-grind-ios")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://git.opengrind.org/open-grind/open-grind")!) {
                    Label("The Open Grind Project", systemImage: "globe")
                }
            } footer: {
                Text(
                    "Open Grind for iOS is free software under the MIT License, based on Open Grind by its contributors. The logo is in the public domain (CC0)."
                )
            }

            Section {
            } footer: {
                Text(
                    "Open Grind is not affiliated with, endorsed or sponsored by Grindr LLC. Grindr is a trademark of Grindr LLC."
                )
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What the app stores and sends, in plain words.
struct PrivacyView: View {
    var body: some View {
        List {
            Point(
                systemImage: "network", title: "Only Grindr",
                text:
                    "The app connects only to Grindr's servers. There are no analytics, ads or crash reporters."
            )
            Point(
                systemImage: "location", title: "Rounded Location",
                text: "Before your location is sent, it is rounded to a square about 100 meters across.")
            Point(
                systemImage: "key", title: "Keychain",
                text:
                    "Your session token is kept in the iOS Keychain on this device only. Your password is never stored."
            )
            Point(
                systemImage: "photo", title: "Photo Metadata Removed",
                text: "Photos you send are re-encoded first, which removes where and when they were taken.")
            Point(
                systemImage: "internaldrive", title: "Cache",
                text: "Photos are cached on this iPhone for up to a week and deleted when you sign out.")
        }
        .navigationTitle("Your Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct Point: View {
        let systemImage: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey

        var body: some View {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(text).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 4)
        }
    }
}
