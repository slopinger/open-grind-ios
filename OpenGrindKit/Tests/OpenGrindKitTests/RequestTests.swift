import Foundation
import Testing

@testable import OpenGrindKit

struct RequestTests {
    @Test func defaultFiltersSendOnlyTheLocation() async throws {
        let transport = FakeTransport { _ in .json(#"{"items":[],"nextPage":null}"#) }
        let api = GrindrAPI(transport: transport)
        _ = try await api.cascade(near: "u33dc0cppvbz", filters: BrowseFilters(), page: nil)
        let request = try #require(transport.requests.first)
        #expect(request.method == .get)
        let components = try #require(URLComponents(string: request.path))
        #expect(components.path == "/v4/cascade")
        #expect(
            components.queryItems == [
                URLQueryItem(name: "nearbyGeoHash", value: Geohash.coarsen("u33dc0cppvbz"))
            ])
    }

    @Test func filtersBecomeCascadeQueryItems() {
        var filters = BrowseFilters()
        filters.onlineOnly = true
        filters.ages = 25...40
        filters.positions = [.versBottom, .top]
        filters.weights = 60_000...BrowseFilters.weightBounds.upperBound
        let items = Dictionary(
            uniqueKeysWithValues: filters.queryItems().map { ($0.name, $0.value ?? "") })
        #expect(
            items == [
                "onlineOnly": "true", "ageMin": "25", "ageMax": "40", "sexualPositions": "1,4",
                "weightGramsMin": "60000", "weightGramsMax": "272156",
            ])
        #expect(filters.activeCount == 4)
        #expect(BrowseFilters().activeCount == 0)
    }

    @Test func profileEditsSendOnlyChangedFields() throws {
        let profile = Profile(
            id: 1, displayName: "Ada", aboutMe: "Hello", age: 30, height: 170, position: .top,
            lookingFor: [.chat], hivStatus: .preferToDiscuss)
        let original = ProfileEdit(profile)
        #expect(original.hivStatus == nil, "prefer to discuss can be shown but not set")
        #expect(original.patch(from: original) == nil)

        var edit = original
        edit.aboutMe = "  "
        edit.position = nil
        edit.lookingFor = [.friends, .chat]
        edit.age = 31
        let patch = try #require(edit.patch(from: original))
        #expect(
            patch
                == .object([
                    "aboutMe": .null, "sexualPosition": .null, "lookingFor": .ints([2, 4]), "age": .int(31),
                ]))
        let applied = edit.applied(to: profile)
        #expect(applied.aboutMe == nil && applied.position == nil && applied.age == 31)
        #expect(applied.lookingFor == [.chat, .friends])
    }

    @Test func overlongTextIsInvalid() {
        var edit = ProfileEdit(Profile(id: 1))
        #expect(edit.isValid)
        edit.displayName = String(repeating: "x", count: ProfileEdit.maxDisplayNameLength + 1)
        #expect(!edit.isValid)
    }

    @Test func messagesAreSentAsDirectMessages() async throws {
        let transport = FakeTransport { _ in
            .json(
                #"{"messageId":"m","conversationId":"1:2","senderId":1,"timestamp":1,"type":"Text","body":{"text":"hi"}}"#
            )
        }
        let message = try await GrindrAPI(transport: transport).send(.text("hi"), to: 2)
        #expect(message.content == .text("hi"))
        let body = try #require(transport.requests.first?.jsonObject)
        #expect(body["type"] as? String == "Text")
        #expect((body["target"] as? [String: Any])?["targetId"] as? Int == 2)
        #expect((body["target"] as? [String: Any])?["type"] as? String == "Direct")
        #expect((body["body"] as? [String: Any])?["text"] as? String == "hi")
    }

    @Test func profilesAreRequestedInBatchesOfThirty() async throws {
        let transport = FakeTransport { request in
            let ids = request.jsonObject?["targetProfileIds"] as? [Int] ?? []
            let profiles = ids.map { #"{"profileId":\#($0)}"# }.joined(separator: ",")
            return .json(#"{"profiles":[\#(profiles)]}"#)
        }
        let summaries = try await GrindrAPI(transport: transport).profiles(Array(1...65))
        #expect(summaries.map(\.id) == Array(1...65))
        #expect(transport.requests.count == 3)
    }

    @Test func unavailableProfilesThrow() async {
        let transport = FakeTransport { _ in .json(#"{"profiles":[{"profileId":5,"displayName":"3"}]}"#)
        }
        await #expect(throws: GrindrError.unavailable) {
            try await GrindrAPI(transport: transport).profile(5)
        }
    }

    @Test func malformedResponsesAreInvalidResponses() async {
        let transport = FakeTransport { _ in .json("not json") }
        await #expect {
            try await GrindrAPI(transport: transport).receivedTaps()
        } throws: { error in
            if case GrindrError.invalidResponse = error { return true }
            return false
        }
    }
}
