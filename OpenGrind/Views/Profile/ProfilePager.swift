import OpenGrindKit
import SwiftUI

/// Profiles from the grid side by side: swipe sideways to the next or previous
/// one, in grid order. Only the profile on screen loads and counts as viewed.
struct ProfilePager: View {
    /// The tile that was tapped.
    let start: GridProfile
    /// The grid's namespace, so swiping down zooms back into the tile on screen.
    let transition: Namespace.ID

    @Environment(AccountSession.self) private var session
    @State private var current: ProfileID?

    init(start: GridProfile, transition: Namespace.ID) {
        self.start = start
        self.transition = transition
        _current = State(initialValue: start.id)
    }

    var body: some View {
        // The tapped profile may have left the grid meanwhile, e.g. after a refresh.
        let grid = session.browse.profiles
        let profiles = grid.contains { $0.id == start.id } ? grid : [start]
        let shown = current ?? start.id
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(profiles) { tile in
                    ProfileScreen(profileID: tile.id, preview: tile, isCurrentPage: tile.id == shown)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $current)
        .scrollIndicators(.hidden)
        .navigationTransition(.zoom(sourceID: shown, in: transition))
        .task(id: shown) {
            // More of the grid, as when scrolling it, so swiping doesn't run out early.
            if let tile = profiles.first(where: { $0.id == shown }) {
                await session.browse.loadMoreIfNeeded(after: tile)
            }
        }
    }
}
