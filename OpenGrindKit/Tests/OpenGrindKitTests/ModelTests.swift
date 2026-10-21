import Foundation
import Testing

@testable import OpenGrindKit

@MainActor
struct ModelTests {
    private func session(_ transport: FakeTransport, me: ProfileID = 1) -> AccountSession {
        AccountSession(
            profileID: me, api: GrindrAPI(transport: transport),
            location: FixedLocation(geohash: "u33dc0cppvbz"))
    }

    private func message(_ id: String, from sender: ProfileID, at seconds: Int64, _ text: String)
        -> Message
    {
        Message(
            id: id, conversationID: "1:2", senderID: sender, date: Date(milliseconds: seconds * 1000),
            content: .text(text))
    }

    // MARK: Chat

    @Test func sendingShowsTheMessageAtOnceAndReplacesItWithTheServersCopy() async throws {
        let transport = FakeTransport { request in
            guard request.path == "/v4/chat/message/send" else { return .json("{}") }
            return .json(
                #"{"messageId":"srv","conversationId":"1:2","senderId":1,"timestamp":1,"type":"Text","body":{"text":"hi"}}"#
            )
        }
        let chat = session(transport).chat(with: 2)
        chat.draft = "  hi "
        await chat.sendDraft()
        #expect(chat.draft.isEmpty)
        #expect(chat.items.map(\.id) == ["srv"])
        #expect(chat.items.first?.delivery == .sent)
    }

    @Test func aFailedSendCanBeRetried() async throws {
        let transport = FakeTransport { _ in throw GrindrError.offline }
        let chat = session(transport).chat(with: 2)
        await chat.send(.text("hello"))
        let failed = try #require(chat.items.first)
        #expect(failed.delivery == .failed)
        #expect(chat.actionFailure == .grindr(.offline))

        transport.respond { _ in
            .json(
                #"{"messageId":"ok","conversationId":"1:2","senderId":1,"timestamp":1,"type":"Text","body":{"text":"hello"}}"#
            )
        }
        await chat.retry(failed)
        #expect(chat.items.map(\.id) == ["ok"])
    }

    @Test func theWebsocketEchoOfASentMessageIsNotShownTwice() async throws {
        let transport = FakeTransport()
        let session = session(transport)
        let chat = session.chat(with: 2)
        let echo = message("srv", from: 1, at: 1, "hi")
        transport.respond { request in
            guard request.path == "/v4/chat/message/send" else { return .json("{}") }
            // The websocket delivers the message before the REST call returns.
            Task { @MainActor in session.simulate(.message(echo)) }
            Thread.sleep(forTimeInterval: 0.05)
            return .json(
                #"{"messageId":"srv","conversationId":"1:2","senderId":1,"timestamp":1000,"type":"Text","body":{"text":"hi"}}"#
            )
        }
        await chat.send(.text("hi"))
        #expect(await eventually { chat.items.allSatisfy { $0.delivery == .sent } })
        #expect(chat.items.map(\.id) == ["srv"])
    }

    @Test func incomingMessagesAreOrderedAndUnsendsApplied() async throws {
        let transport = FakeTransport { _ in
            .json(
                #"{"lastReadTimestamp":null,"profile":null,"messages":[{"messageId":"b","conversationId":"1:2","senderId":2,"timestamp":2000,"type":"Text","body":{"text":"second"}},{"messageId":"a","conversationId":"1:2","senderId":1,"timestamp":1000,"type":"Text","body":{"text":"first"}}]}"#
            )
        }
        let session = session(transport)
        let chat = session.chat(with: 2)
        await chat.reload()
        #expect(chat.items.map(\.id) == ["a", "b"])

        session.simulate(.message(message("c", from: 2, at: 3, "third")))
        session.simulate(.message(message("late", from: 2, at: 1, "out of order")))
        #expect(chat.items.map(\.id) == ["a", "late", "b", "c"])

        var retract = message("r", from: 2, at: 4, "")
        retract.content = .unsupported(.retract)
        retract.retractedMessageID = "b"
        session.simulate(.message(retract))
        #expect(chat.items.first { $0.id == "b" }?.message.content == .unsent)
        #expect(!chat.items.contains { $0.id == "r" })
    }

    @Test func readReceiptsMarkTheLastReadOutgoingMessage() async {
        let session = session(FakeTransport())
        let chat = session.chat(with: 2)
        session.simulate(.message(message("a", from: 1, at: 1, "one")))
        session.simulate(.message(message("b", from: 1, at: 3, "two")))
        #expect(chat.lastReadOutgoingID == nil)
        session.simulate(
            .conversationRead(conversationID: "1:2", profileID: 2, date: Date(milliseconds: 2000)))
        #expect(chat.lastReadOutgoingID == "a")
        // Our own read from another device says nothing about the other side.
        session.simulate(
            .conversationRead(conversationID: "1:2", profileID: 1, date: Date(milliseconds: 9000)))
        #expect(chat.lastReadOutgoingID == "a")
    }

    @Test func anOpenChatMarksIncomingMessagesRead() async {
        let transport = FakeTransport()
        let session = session(transport)
        let chat = session.chat(with: 2)
        chat.appeared()
        session.simulate(.message(message("x", from: 2, at: 1, "hey")))
        #expect(
            await eventually {
                transport.requests.contains { $0.path == "/v4/chat/conversation/1:2/read/x" }
            })
        chat.disappeared()
        #expect(session.inbox.openConversationID == nil)
    }

    // MARK: Inbox

    @Test func inboxFollowsRealtimeMessages() async {
        let transport = FakeTransport { _ in
            .json(
                #"{"entries":[{"type":"full_conversation_v1","data":{"conversationId":"1:3","name":"C","participants":[],"lastActivityTimestamp":5000,"unreadCount":0}},{"type":"full_conversation_v1","data":{"conversationId":"1:2","name":"B","participants":[],"lastActivityTimestamp":4000,"unreadCount":0}}],"nextPage":null}"#
            )
        }
        let session = session(transport)
        let inbox = session.inbox
        await inbox.refresh()
        #expect(inbox.conversations.map(\.id) == ["1:3", "1:2"])

        session.simulate(.message(message("m", from: 2, at: 6, "hi")))
        #expect(inbox.conversations.map(\.id) == ["1:2", "1:3"])
        #expect(inbox.conversations.first?.unreadCount == 1)
        #expect(inbox.conversations.first?.preview?.text == "hi")
        #expect(inbox.unreadCount == 1)

        session.simulate(.message(message("m", from: 2, at: 6, "hi")))
        var retract = message("r", from: 2, at: 7, "")
        retract.content = .unsupported(.retract)
        retract.retractedMessageID = "m"
        session.simulate(.message(retract))
        #expect(inbox.unreadCount == 1, "a repeated delivery or an unsend is no new message")

        session.simulate(.conversationRead(conversationID: "1:2", profileID: 1, date: .now))
        #expect(inbox.unreadCount == 0)

        session.simulate(.conversationsDeleted(["1:3"]))
        #expect(inbox.conversations.map(\.id) == ["1:2"])
    }

    @Test func pinnedConversationsStayOnTopAndFailedActionsRollBack() async {
        let transport = FakeTransport { _ in
            .json(
                #"{"entries":[{"type":"full_conversation_v1","data":{"conversationId":"1:3","name":"C","participants":[],"lastActivityTimestamp":5000,"unreadCount":0}},{"type":"full_conversation_v1","data":{"conversationId":"1:2","name":"B","participants":[],"lastActivityTimestamp":4000,"unreadCount":0}}],"nextPage":null}"#
            )
        }
        let inbox = session(transport).inbox
        await inbox.refresh()
        let older = inbox.conversations[1]
        await inbox.setPinned(older, true)
        #expect(inbox.conversations.map(\.id) == ["1:2", "1:3"])

        transport.respond { _ in throw GrindrError.offline }
        await inbox.delete(inbox.conversations[0])
        #expect(inbox.conversations.map(\.id) == ["1:2", "1:3"])
        #expect(inbox.actionFailure == .grindr(.offline))
    }

    // MARK: Browse

    @Test func browseReportsLocationProblems() async {
        struct NoLocation: LocationProviding {
            func currentGeohash() async throws -> String { throw LocationError.denied }
        }
        let browse = BrowseModel(api: GrindrAPI(transport: FakeTransport()), location: NoLocation())
        await browse.loadIfNeeded()
        #expect(browse.state == .failed(.location(.denied)))
    }

    @Test func exploringWorksWithoutYourLocation() async throws {
        struct NoLocation: LocationProviding {
            func currentGeohash() async throws -> String { throw LocationError.denied }
        }
        let transport = FakeTransport { _ in
            .json(#"{"items":[{"type":"full_profile_v1","data":{"profileId":1}}],"nextPage":2}"#)
        }
        let browse = BrowseModel(api: GrindrAPI(transport: transport), location: NoLocation())
        await browse.explore(ExplorePlace(latitude: 52.52, longitude: 13.405))
        #expect(browse.state == .loaded)
        await browse.loadMore()
        let pages = transport.requests.compactMap { URLComponents(string: $0.path)?.queryItems }
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { items in !items.contains { $0.name == "nearbyGeoHash" } })
    }

    @Test func browsePagesUntilTheServerStops() async {
        let transport = FakeTransport { request in
            let page = URLComponents(string: request.path)?.queryItems?.first { $0.name == "pageNumber" }?
                .value
            return page == nil
                ? .json(#"{"items":[{"type":"full_profile_v1","data":{"profileId":1}}],"nextPage":2}"#)
                : .json(#"{"items":[{"type":"full_profile_v1","data":{"profileId":2}}],"nextPage":null}"#)
        }
        let browse = session(transport).browse
        await browse.loadIfNeeded()
        #expect(browse.profiles.map(\.id) == [1])
        await browse.loadMore()
        #expect(browse.profiles.map(\.id) == [1, 2])
        #expect(!browse.canLoadMore)
    }

    // MARK: Account

    @Test func signingInStoresCredentialsAndSigningOutForgetsThem() async throws {
        let transport = FakeTransport()
        transport.signInResult = SignInResult(profileID: 77)
        let store = InMemoryCredentialStore()
        let account = AccountController(
            transport: transport, credentials: store, location: FixedLocation(geohash: "u33dc0cppvbz"))
        #expect(account.session == nil)

        try await account.signIn(email: " ada@example.com ", password: "secret")
        #expect(account.session?.profileID == 77)
        #expect(await eventually { store.loadCredentials() != nil })

        await account.signOut()
        #expect(account.session == nil)
        #expect(store.loadCredentials() == nil)
        #expect(account.signedOutReason == nil)
    }

    @Test func storedCredentialsResumeTheSession() {
        let store = InMemoryCredentialStore(credentials: #"{"profile_id":"5","auth_token":"t"}"#)
        let account = AccountController(
            transport: FakeTransport(), credentials: store,
            location: FixedLocation(geohash: "u33dc0cppvbz"))
        #expect(account.session?.profileID == 5)
    }

    @Test func aBanSignsOutWithAReason() async {
        let transport = FakeTransport()
        let store = InMemoryCredentialStore(credentials: #"{"profile_id":"5","auth_token":"t"}"#)
        let account = AccountController(
            transport: transport, credentials: store, location: FixedLocation(geohash: "u33dc0cppvbz"))
        transport.emit(.sessionEnded(banned: true, reason: "spam"))
        #expect(await eventually { account.session == nil })
        #expect(account.signedOutReason == .banned(reason: "spam"))
    }
}
