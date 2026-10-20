import Foundation
import Testing

@testable import OpenGrindKit

/// The demo goes through the same decoders and models as the real API, so
/// these also check that its JSON matches what the decoders expect.
@MainActor
struct DemoTests {
    /// The controller delivers realtime events, so tests keep it alive.
    private let account = AccountController(
        transport: DemoTransport(replyDelay: .milliseconds(20)), credentials: InMemoryCredentialStore(),
        location: FixedLocation(geohash: DemoTransport.geohash), isDemo: true)

    private func signedIn() async throws -> AccountSession {
        try await account.signIn(email: "demo", password: "")
        return try #require(account.session)
    }

    @Test func filtersAreRememberedButNotTheExploredPlace() async throws {
        let defaults = try #require(UserDefaults(suiteName: "DemoTests.\(UUID().uuidString)"))
        let preferences = DefaultsPreferenceStore(defaults: defaults)
        let credentials = InMemoryCredentialStore()
        func launch() -> AccountController {
            AccountController(
                transport: DemoTransport(), credentials: credentials,
                location: FixedLocation(geohash: DemoTransport.geohash), preferences: preferences, isDemo: true)
        }

        let first = launch()
        try await first.signIn(email: "demo", password: "")
        var filters = BrowseFilters()
        filters.onlineOnly = true
        filters.tags = ["hiking"]
        let session = try #require(first.session)
        await session.browse.apply(filters)
        await session.browse.explore(ExplorePlace(latitude: 48.86, longitude: 2.35, name: "Paris"))

        let relaunched = try #require(launch().session, "the stored credentials resume the session")
        #expect(relaunched.browse.filters == filters)
        #expect(relaunched.browse.exploring == nil)

        await first.signOut()
        #expect(preferences.browseFilters(for: session.profileID) == nil, "signing out forgets them")
    }

    @Test func everyTabLoads() async throws {
        let session = try await signedIn()
        await session.browse.loadIfNeeded()
        await session.inbox.loadIfNeeded()
        await session.interest.loadIfNeeded()
        await session.me.loadIfNeeded()

        #expect(session.browse.state == .loaded)
        #expect(session.browse.profiles.count == 30)
        #expect(session.browse.canLoadMore)
        await session.browse.loadMore()
        #expect(session.browse.profiles.count > 30)
        #expect(!session.browse.canLoadMore)
        let distances = session.browse.profiles.compactMap(\.distance)
        #expect(distances == distances.sorted())

        #expect(session.inbox.state == .loaded)
        #expect(session.inbox.conversations.count == 6)
        #expect(session.inbox.unreadCount > 0)
        #expect(session.inbox.conversations.first?.isPinned == true)

        #expect(session.interest.taps.count == 6)
        #expect(session.interest.views.viewers.count == 9)
        #expect(session.interest.views.hiddenCount == 4)

        #expect(session.me.profile?.displayName == "Alex")
        #expect(session.catalogs.genders.count == 5)
        #expect(session.catalogs.tags != nil, "your profile loads the catalogs with it")
    }

    @Test func filtersApply() async throws {
        let session = try await signedIn()
        var filters = BrowseFilters()
        filters.onlineOnly = true
        await session.browse.apply(filters)
        #expect(!session.browse.profiles.isEmpty)
        #expect(session.browse.profiles.allSatisfy { $0.isOnline() })
    }

    @Test func tagFiltersMatchProfileTags() async throws {
        let session = try await signedIn()
        await session.catalogs.loadTags()
        let catalog = try #require(session.catalogs.tags)
        #expect(catalog.tag(forKey: "hiking")?.text == "Hiking")
        var filters = BrowseFilters()
        filters.tags = ["hiking"]
        await session.browse.apply(filters)
        #expect(!session.browse.profiles.isEmpty)
        for tile in session.browse.profiles.prefix(5) {
            let profile = try await session.api.profile(tile.id)
            #expect(profile.tags.contains("Hiking"))
        }
    }

    @Test func demoProfilesReply() async throws {
        let session = try await signedIn()
        let chat = session.chat(with: 20_000)
        await chat.loadIfNeeded()
        let before = chat.items.count
        chat.draft = "Hi there"
        await chat.sendDraft()
        #expect(chat.items.count == before + 1)
        #expect(await eventually { chat.items.count == before + 2 })
        #expect(chat.items.last.map(chat.isOutgoing) == false)
    }

    @Test func profilesCanBeOpenedEditedAndBlocked() async throws {
        let session = try await signedIn()
        await session.browse.loadIfNeeded()
        let tile = try #require(session.browse.profiles.first { $0.displayName != nil })

        let model = ProfileModel(profileID: tile.id, session: session)
        await model.load()
        #expect(model.profile?.displayName == tile.displayName)
        await model.setFavorite(true)
        #expect(model.profile?.isFavorite == true)
        #expect(session.browse.profiles.first { $0.id == tile.id }?.isFavorite == true)

        try await model.block()
        #expect(!session.browse.profiles.contains { $0.id == tile.id })
        await session.me.loadBlocked()
        #expect(session.me.blocked.first?.id == tile.id)
        #expect(session.me.blocked.first?.summary?.displayName == tile.displayName)

        await session.me.loadIfNeeded()
        let profile = try #require(session.me.profile)
        var edit = ProfileEdit(profile)
        edit.aboutMe = "Updated"
        edit.position = .top
        edit.tags = ["hiking"]
        edit.genderIDs = [4]
        edit.pronounIDs = [1, 3]
        try await session.me.save(edit)
        #expect(session.me.profile?.tags == ["hiking"])
        await session.me.refresh()
        let saved = try #require(session.me.profile)
        #expect(saved.aboutMe == "Updated")
        #expect(saved.position == .top)
        // The demo sends the texts back, as other profiles carry them; MeModel keeps keys.
        #expect(saved.tags == ["hiking"])
        #expect(saved.genderIDs == [4] && saved.pronounIDs == [1, 3])
    }

    @Test func photosCanBeSent() async throws {
        let session = try await signedIn()
        let chat = session.chat(with: 20_000)
        await chat.sendPhoto(Data([0xFF, 0xD8, 0xFF]))
        guard case .image(let url, _, _) = chat.items.last?.message.content else {
            Issue.record("expected an image, got \(String(describing: chat.items.last))")
            return
        }
        let media = try await session.api.transport.fetchMedia(at: url, maxBytes: 1_000_000)
        #expect(media.data == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test func profilePhotosCanBeAddedReorderedAndDeleted() async throws {
        let session = try await signedIn()
        let me = session.me
        await me.loadIfNeeded()
        let before = try #require(me.profile?.photos)
        await me.addPhoto(Data([0xFF, 0xD8, 0xFF]), width: 400, height: 300)
        let added = try #require(me.profile?.photos.last)
        #expect(me.profile?.photos.count == before.count + 1)
        #expect(added.isPendingReview)

        let reordered = [added] + before
        await me.setPhotoOrder(reordered)
        await me.refresh()
        #expect(me.profile?.photos == reordered, "the new photo is now the main one and still in review")

        await me.deletePhoto(added)
        #expect(me.profile?.photos == before, "the next photo is the main one again")
        await me.refresh()
        #expect(me.profile?.photos == before)
        #expect(me.actionFailure == nil)
    }

    @Test func exploringAnotherPlaceChangesTheGrid() async throws {
        let session = try await signedIn()
        let browse = session.browse
        await browse.loadIfNeeded()
        let nearby = browse.profiles.map(\.id)
        let home = try #require(browse.currentPlace)
        await browse.explore(ExplorePlace(latitude: 40.7128, longitude: -74.006, name: "New York"))
        #expect(browse.exploring?.name == "New York")
        #expect(!browse.profiles.isEmpty && browse.profiles.map(\.id) != nearby)
        #expect(browse.currentPlace == home, "exploring doesn't move you")
        await browse.explore(nil)
        #expect(browse.profiles.map(\.id) == nearby)
    }
}
