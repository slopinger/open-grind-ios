import OpenGrindKit
import SwiftUI

/// Your profile, account and app settings.
struct MeView: View {
    @Environment(AccountSession.self) private var session
    @Environment(AppModel.self) private var app
    @State private var path: [Route] = []
    @State private var isEditing = false
    @State private var isConfirmingSignOut = false

    private var me: MeModel { session.me }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if app.isDemo {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("You're Using the Demo").font(.headline)
                                Text("Everyone here is made up. Nothing is sent to Grindr.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "theatermasks.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                Section {
                    header
                    Button("Edit Profile", systemImage: "pencil") { isEditing = true }
                        .disabled(me.profile == nil)
                    NavigationLink(value: Route.profile(session.profileID)) {
                        Label("Preview Profile", systemImage: "eye")
                    }
                }

                Section("Privacy & Safety") {
                    NavigationLink {
                        BlockedProfilesView()
                    } label: {
                        Label("Blocked", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("How Open Grind Handles Your Data", systemImage: "hand.raised.square.on.square")
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Open Grind", systemImage: "info.circle")
                    }
                }

                Section {
                    Button(app.isDemo ? "Leave Demo" : "Sign Out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                }
            }
            .navigationTitle("Profile")
            .refreshable { await me.refresh() }
            .routeDestinations()
            .sheet(isPresented: $isEditing) {
                if let profile = me.profile {
                    EditProfileView(profile: profile, me: me)
                }
            }
            .confirmationDialog(
                app.isDemo ? "Leave the Demo?" : "Sign Out?", isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button(app.isDemo ? "Leave Demo" : "Sign Out", role: .destructive) {
                    Task { await app.signOut() }
                }
            } message: {
                if !app.isDemo {
                    Text("Open Grind forgets your session and cached photos on this iPhone.")
                }
            }
        }
        .task { await me.loadIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Avatar(photoHash: me.profile?.primaryPhoto?.mediaHash, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                if let profile = me.profile {
                    Text(profile.displayName ?? String(localized: "No name"))
                        .font(.title3.bold())
                    if let age = profile.age {
                        Text("\(age) years")
                            .foregroundStyle(.secondary)
                    }
                } else if let failure = me.state.failure {
                    Text(FailureText(failure).title)
                        .font(.headline)
                    Text("Pull to refresh.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Profiles you blocked, with a way to unblock them.
struct BlockedProfilesView: View {
    @Environment(AccountSession.self) private var session
    @State private var pendingUnblock: MeModel.BlockedEntry?

    private var me: MeModel { session.me }

    var body: some View {
        @Bindable var me = me
        Group {
            switch me.blockedState {
            case .idle,
                .loading where me.blocked.isEmpty:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let failure) where me.blocked.isEmpty:
                FailureView(failure: failure) { await me.loadBlocked() }
            default:
                List(me.blocked) { entry in
                    HStack(spacing: 12) {
                        Avatar(photoHash: entry.summary?.photoHash, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.summary?.displayName ?? String(localized: "No name"))
                            if let date = entry.blockedAt {
                                Text("Blocked \(date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Unblock") { pendingUnblock = entry }
                            .buttonStyle(.bordered)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Unblock") { pendingUnblock = entry }
                }
                .overlay {
                    if me.blocked.isEmpty {
                        ContentUnavailableView(
                            "No Blocked Profiles", systemImage: "hand.raised",
                            description: Text("Profiles you block appear here."))
                    }
                }
                .refreshable { await me.loadBlocked() }
            }
        }
        .navigationTitle("Blocked")
        .task { await me.loadBlocked() }
        .confirmationDialog(
            "Unblock?", isPresented: isConfirming, titleVisibility: .visible, presenting: pendingUnblock
        ) { entry in
            Button("Unblock") { Task { await me.unblock(entry) } }
        } message: { _ in
            Text("You'll be able to see each other and chat again.")
        }
        .failureAlert($me.actionFailure)
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingUnblock != nil }, set: { if !$0 { pendingUnblock = nil } })
    }
}
