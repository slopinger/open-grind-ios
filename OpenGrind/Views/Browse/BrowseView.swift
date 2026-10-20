import OpenGrindKit
import SwiftUI

/// The grid of profiles nearby.
struct BrowseView: View {
    @Environment(AccountSession.self) private var session
    @State private var isShowingFilters = false
    @State private var isShowingExplore = false
    @Namespace private var transition

    private var browse: BrowseModel { session.browse }

    var body: some View {
        // Untyped: the stack holds grid tiles as well as routes.
        NavigationStack {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    ExploreBar(place: browse.exploring) {
                        isShowingExplore = true
                    } stop: {
                        Task { await browse.explore(nil) }
                    }
                }
                .navigationTitle(browse.exploring == nil ? "Nearby" : "Explore")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isShowingFilters = true
                        } label: {
                            Label(
                                "Filters",
                                systemImage: browse.filters.isDefault
                                    ? "line.3.horizontal.decrease.circle"
                                    : "line.3.horizontal.decrease.circle.fill")
                        }
                        .badge(browse.filters.activeCount)
                        .accessibilityValue(
                            browse.filters.isDefault
                                ? Text("None") : Text("\(browse.filters.activeCount) active"))
                    }
                }
                .sheet(isPresented: $isShowingFilters) {
                    FilterSheet(filters: browse.filters) { filters in
                        Task { await browse.apply(filters) }
                    }
                }
                .sheet(isPresented: $isShowingExplore) {
                    ExploreSheet(
                        start: browse.exploring ?? browse.currentPlace, isExploring: browse.exploring != nil
                    ) { place in
                        Task { await browse.explore(place) }
                    }
                }
                .routeDestinations()
                .navigationDestination(for: GridProfile.self) { tile in
                    ProfileScreen(profileID: tile.id, preview: tile)
                        .navigationTransition(.zoom(sourceID: tile.id, in: transition))
                }
        }
        .task { await browse.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch browse.state {
        case .idle,
            .loading where browse.profiles.isEmpty:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let failure) where browse.profiles.isEmpty:
            FailureView(failure: failure) { await browse.refresh() }
        default:
            if browse.profiles.isEmpty {
                emptyState
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 2)], spacing: 2) {
                ForEach(browse.profiles) { profile in
                    NavigationLink(value: profile) {
                        ProfileTile(profile: profile)
                            .matchedTransitionSource(id: profile.id, in: transition)
                    }
                    .buttonStyle(.plain)
                    .task { await browse.loadMoreIfNeeded(after: profile) }
                }
            }
            if browse.isLoadingMore {
                ProgressView()
                    .padding()
                    .accessibilityLabel("Loading more profiles")
            }
        }
        .refreshable { await browse.refresh() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if browse.filters.isDefault, browse.exploring != nil {
            ContentUnavailableView {
                Label("No One Here", systemImage: "binoculars")
            } description: {
                Text("No one is around this place right now. Try another one.")
            } actions: {
                Button("Back to My Location") {
                    Task { await browse.explore(nil) }
                }
                .buttonStyle(.bordered)
            }
        } else if browse.filters.isDefault {
            ContentUnavailableView {
                Label("No One Nearby", systemImage: "person.2.slash")
            } description: {
                Text("Pull to refresh or check back later.")
            }
        } else {
            ContentUnavailableView {
                Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No one nearby matches your filters.")
            } actions: {
                Button("Clear Filters") {
                    Task { await browse.apply(BrowseFilters()) }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// Looks like a search field: shows where the grid is and opens the map to
/// explore somewhere else.
private struct ExploreBar: View {
    let place: ExplorePlace?
    let open: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: place == nil ? "magnifyingglass" : "binoculars.fill")
                        .foregroundStyle(place == nil ? Color.secondary : Color.brand)
                    if let place {
                        Text(place.name ?? String(localized: "Selected Place"))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text("Explore Another Place")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "map")
                        .foregroundStyle(.tint)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Color(.tertiarySystemFill), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                place.map { Text("Exploring \($0.name ?? String(localized: "Selected Place"))") }
                    ?? Text("Explore Another Place")
            )
            .accessibilityHint("Opens a map to choose a place.")

            if place != nil {
                Button("Back to My Location", systemImage: "location.fill", action: stop)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(Color(.tertiarySystemFill), in: .circle)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .animation(.default, value: place)
    }
}

/// A square photo with name, age, presence and unread count.
struct ProfileTile: View {
    let profile: GridProfile

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(url: profile.photoURL, pointSize: 180)
            }
            .overlay(alignment: .bottom) { caption }
            .overlay(alignment: .topTrailing) { badges }
            .clipped()
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    private var caption: some View {
        HStack(spacing: 4) {
            if profile.isOnline() {
                OnlineIndicator()
                    .frame(width: 8, height: 8)
            }
            Text(profile.displayName ?? "")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            if let age = profile.age {
                Text(age, format: .number)
                    .font(.footnote)
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.top, 16)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if profile.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.brand)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            }
            if profile.unreadCount > 0 {
                Text(profile.unreadCount, format: .number)
                    .font(.caption2.bold())
                    .foregroundStyle(Color.brandForeground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.brand, in: .capsule)
            }
        }
        .padding(5)
    }

    private var accessibilityLabel: Text {
        var parts: [String] = [profile.displayName ?? String(localized: "No name")]
        if let age = profile.age { parts.append(String(localized: "\(age) years")) }
        if let distance = Formatting.distance(profile.distance) { parts.append(distance) }
        if profile.isOnline() { parts.append(String(localized: "Online")) }
        if profile.isFavorite { parts.append(String(localized: "Favorite")) }
        if profile.unreadCount > 0 {
            parts.append(String(localized: "\(profile.unreadCount) unread messages"))
        }
        return Text(parts.joined(separator: ", "))
    }
}
