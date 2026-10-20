import OpenGrindKit
import SwiftUI

/// Taps you received and who viewed your profile.
struct InterestView: View {
    enum Section: String, CaseIterable, Identifiable {
        case taps, views
        var id: Self { self }
    }

    @Environment(AccountSession.self) private var session
    @SceneStorage("interestSection") private var section = Section.taps
    @State private var path: [Route] = []

    private var interest: InterestModel { session.interest }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch section {
                case .taps: taps
                case .views: views
                }
            }
            .navigationTitle("Interest")
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $section) {
                    Text("Taps").tag(Section.taps)
                    Text("Views").tag(Section.views)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .refreshable { await interest.refresh() }
            .routeDestinations()
        }
        .task { await interest.loadIfNeeded() }
    }

    @ViewBuilder
    private var taps: some View {
        switch interest.tapsState {
        case .idle,
            .loading where interest.taps.isEmpty:
            loading
        case .failed(let failure) where interest.taps.isEmpty:
            FailureView(failure: failure) { await interest.refreshTaps() }
        default:
            List(interest.taps) { tap in
                let row = InterestRow(
                    name: tap.displayName, photoHash: tap.photoHash, isOnline: tap.isOnline(), date: tap.date,
                    distance: tap.distance, isLocked: !tap.isViewable
                ) {
                    if let type = tap.type {
                        Text(type.emoji)
                            .font(.title2)
                            .accessibilityLabel(type.localizedName)
                    }
                    if tap.isMutual {
                        Text("Mutual")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandForeground)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.brand, in: .capsule)
                    }
                }
                if tap.isViewable {
                    NavigationLink(value: Route.profile(tap.profileID)) { row }
                } else {
                    row
                }
            }
            .listStyle(.plain)
            .overlay {
                if interest.taps.isEmpty {
                    ContentUnavailableView(
                        "No Taps Yet", systemImage: "flame",
                        description: Text("When someone taps you, they appear here."))
                }
            }
        }
    }

    @ViewBuilder
    private var views: some View {
        switch interest.viewsState {
        case .idle,
            .loading where interest.views.viewers.isEmpty:
            loading
        case .failed(let failure) where interest.views.viewers.isEmpty:
            FailureView(failure: failure) { await interest.refreshViews() }
        default:
            List {
                SwiftUI.Section {
                    ForEach(interest.views.viewers) { viewer in
                        NavigationLink(value: Route.profile(viewer.profileID)) {
                            InterestRow(
                                name: viewer.displayName, photoHash: viewer.photoHash, isOnline: viewer.isOnline(),
                                date: viewer.lastViewed, distance: viewer.distance, isLocked: false
                            ) {
                                if viewer.viewCount > 1 {
                                    Text("\(viewer.viewCount)×")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Viewed \(viewer.viewCount) times")
                                }
                            }
                        }
                    }
                } footer: {
                    if interest.views.hiddenCount > 0 {
                        Text(
                            "\(interest.views.hiddenCount) more people viewed you. Grindr only shows them with a subscription."
                        )
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if interest.views.viewers.isEmpty && interest.views.hiddenCount == 0 {
                    ContentUnavailableView(
                        "No Views Yet", systemImage: "eye",
                        description: Text("People who look at your profile appear here."))
                }
            }
        }
    }

    private var loading: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A person in the Taps or Views list.
private struct InterestRow<Accessory: View>: View {
    let name: String?
    let photoHash: String?
    let isOnline: Bool
    let date: Date?
    let distance: Double?
    let isLocked: Bool
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Avatar(photoHash: photoHash, size: 52, isOnline: isOnline)
                .blur(radius: isLocked ? 8 : 0)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(isLocked ? String(localized: "Someone") : (name ?? String(localized: "No name")))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                let details = [date.map { Formatting.listTime($0) }, Formatting.distance(distance)]
                    .compactMap(\.self)
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Requires a subscription")
            }
            accessory
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
