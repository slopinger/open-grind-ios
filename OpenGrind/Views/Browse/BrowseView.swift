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
                .navigationTitle(browse.exploring == nil ? "Nearby" : "Explore")
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
        if browse.profiles.isEmpty {
            VStack(spacing: 0) {
                bar
                LoadStateView(
                    browse.state, isEmpty: true, retry: { await browse.refresh() }, recovery: backToMyLocation
                ) {
                    emptyState
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            grid
        }
    }

    /// A place can fail to load for good; going back to your location always works.
    private var backToMyLocation: FailureView.Recovery? {
        guard browse.exploring != nil else { return nil }
        return FailureView.Recovery(title: "Back to My Location") {
            Task { await browse.explore(nil) }
        }
    }

    /// Part of the content rather than a safe area inset, so it sits below the large
    /// title and scrolls with the grid instead of covering the title.
    private var bar: some View {
        BrowseBar(place: browse.exploring, activeFilters: browse.filters.activeCount) {
            isShowingExplore = true
        } stopExploring: {
            Task { await browse.explore(nil) }
        } showFilters: {
            isShowingFilters = true
        }
    }

    private var grid: some View {
        ScrollView {
            bar
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 2)], spacing: 2) {
                ForEach(browse.profiles) { profile in
                    NavigationLink(value: profile) {
                        ProfileTile(profile: profile, unreadCount: browse.unreadCount(of: profile))
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

/// The row above the grid: a search-field-like button that opens the map to
/// explore somewhere else, and the filters.
private struct BrowseBar: View {
    let place: ExplorePlace?
    let activeFilters: Int
    let explore: () -> Void
    let stopExploring: () -> Void
    let showFilters: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: explore) {
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
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "map")
                        .foregroundStyle(.tint)
                }
                .padding(.horizontal, 14)
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
                Button("Back to My Location", systemImage: "location.fill", action: stopExploring)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(Color(.tertiarySystemFill), in: .circle)
                    .contentShape(.circle)
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
            }

            Button(action: showFilters) {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .fontWeight(.semibold)
                    if activeFilters > 0 {
                        Text(activeFilters, format: .number)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(activeFilters > 0 ? Color.brandForeground : Color.primary)
                .padding(.horizontal, activeFilters > 0 ? 12 : 0)
                .frame(minWidth: 40, minHeight: 40)
                .background(activeFilters > 0 ? Color.brand : Color(.tertiarySystemFill), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters")
            .accessibilityValue(activeFilters > 0 ? Text("\(activeFilters) active") : Text("None"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.default, value: place)
        .animation(.default, value: activeFilters)
    }
}

/// A square photo with name, age, presence and unread count.
struct ProfileTile: View {
    let profile: GridProfile
    let unreadCount: Int

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
            if unreadCount > 0 {
                BrandBadge(Text(unreadCount, format: .number), isSmall: true)
            }
        }
        .padding(5)
    }

    private var accessibilityLabel: Text {
        var parts: [String] = [Formatting.name(profile.displayName)]
        if let age = profile.age { parts.append(String(localized: "\(age) years")) }
        if let distance = Formatting.distance(profile.distance) { parts.append(distance) }
        if profile.isOnline() { parts.append(String(localized: "Online")) }
        if profile.isFavorite { parts.append(String(localized: "Favorite")) }
        if unreadCount > 0 {
            parts.append(String(localized: "\(unreadCount) unread messages"))
        }
        return Text(parts.joined(separator: ", "))
    }
}
