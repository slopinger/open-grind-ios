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
        #expect(session.me.genders.count == 3)
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
        await session.browse.loadTagCatalog()
        let catalog = try #require(session.browse.tagCatalog)
        #expect(catalog.text(forKey: "hiking") == "Hiking")
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
        try await session.me.save(edit)
        await session.me.refresh()
        #expect(session.me.profile?.aboutMe == "Updated")
        #expect(session.me.profile?.position == .top)
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
        await me.refresh()
        #expect(me.profile?.photos == before)
        #expect(me.actionFailure == nil)
    }
}
