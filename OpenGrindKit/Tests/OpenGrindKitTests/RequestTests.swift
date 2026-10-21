import Foundation
import Testing

@testable import OpenGrindKit

struct RequestTests {
    @Test func defaultFiltersSendOnlyTheLocation() async throws {
        let transport = FakeTransport { _ in .json(#"{"items":[],"nextPage":null}"#) }
        let api = GrindrAPI(transport: transport)
        _ = try await api.cascade(.nearby(geohash: "u33dc0cppvbz"), filters: BrowseFilters(), page: nil)
        let request = try #require(transport.requests.first)
        #expect(request.method == .get)
        let components = try #require(URLComponents(string: request.path))
        #expect(components.path == "/v4/cascade")
        #expect(
            components.queryItems == [
                URLQueryItem(name: "nearbyGeoHash", value: Geohash.coarsen("u33dc0cppvbz"))
            ])
    }

    @Test func exploringSendsOnlyTheCoarsenedPlace() async throws {
        let transport = FakeTransport { _ in .json(#"{"items":[],"nextPage":null}"#) }
        let api = GrindrAPI(transport: transport)
        _ = try await api.cascade(.exploring(geohash: "dr5regw3pg6f"), filters: BrowseFilters(), page: nil)
        let request = try #require(transport.requests.first)
        let items = try #require(URLComponents(string: request.path)?.queryItems)
        // Your location would move your profile; Grindr's app never sends both.
        #expect(items == [URLQueryItem(name: "exploreGeoHash", value: Geohash.coarsen("dr5regw3pg6f"))])
    }

    @Test func idsCannotChangeTheRequestPath() async throws {
        let transport = FakeTransport { _ in .json("{}") }
        let api = GrindrAPI(transport: transport)
        try await api.markRead("1:2", through: "x/../../v3/me?a=1#b")
        #expect(transport.requests.first?.path == "/v4/chat/conversation/1:2/read/x%2F..%2F..%2Fv3%2Fme%3Fa=1%23b")

        // Escaped once, also where the request has a query.
        _ = try? await api.messages(in: "x/y?z")
        #expect(transport.requests.last?.path == "/v5/chat/conversation/x%2Fy%3Fz/message?profile=true")
    }

    @Test func filtersBecomeCascadeQueryItems() {
        var filters = BrowseFilters()
        filters.onlineOnly = true
        filters.ages = 25...40
        filters.positions = [.versBottom, .top]
        filters.weights = 60_000...BrowseFilters.weightBounds.upperBound
        filters.heights = 170...BrowseFilters.heightBounds.upperBound
        filters.favoritesOnly = true
        filters.tags = ["hiking", "coffee"]
        let items = Dictionary(
            uniqueKeysWithValues: filters.queryItems().map { ($0.name, $0.value ?? "") })
        // The names of the official app's CascadeRequest.
        #expect(
            items == [
                "onlineOnly": "true", "isFavorites": "true", "ageMin": "25", "ageMax": "40",
                "sexualPositions": "1,4", "heightInCmMin": "170", "heightInCmMax": "241",
                "weightInGramsMin": "60000", "weightInGramsMax": "272156", "tags": "coffee,hiking",
            ])
        #expect(filters.activeCount == 7)
        #expect(BrowseFilters().activeCount == 0)
    }

    @Test func profileEditsSaveTheWholeProfileAsGrindrsAppDoes() throws {
        var profile = Profile(
            id: 1, displayName: "Ada", aboutMe: "Hello", age: 30, height: 170, position: .top,
            tribesImInto: [.bear], lookingFor: [.chat], hivStatus: .preferToDiscuss, instagram: "ada")
        profile.socialNetworks["twitter"] = "ada_t"
        let original = ProfileEdit(profile)
        #expect(original.hivStatus == nil, "prefer to discuss can be shown but not set")
        #expect(original.update(of: profile) == nil, "nothing changed, nothing sent")

        var edit = original
        edit.aboutMe = "  "
        edit.position = nil
        edit.lookingFor = [.friends, .chat]
        edit.age = 31
        guard case .object(let fields) = try #require(edit.update(of: profile)) else {
            Issue.record("expected an object")
            return
        }
        #expect(fields["aboutMe"] == .null && fields["sexualPosition"] == .null)
        #expect(fields["lookingFor"] == .ints([2, 4]) && fields["age"] == .int(31))
        #expect(fields["displayName"] == .string("Ada"), "unchanged fields are sent as they are")
        #expect(
            fields["hivStatus"] == .int(HIVStatus.preferToDiscuss.rawValue), "and kept when the form can't show them")
        #expect(fields["tribesImInto"] == .ints([Tribe.bear.rawValue]))
        #expect(
            fields["socialNetworks"]
                == .object([
                    "instagram": .object(["userId": .string("ada")]),
                    "twitter": .object(["userId": .string("ada_t")]),
                ]))
        let applied = edit.applied(to: profile)
        #expect(applied.aboutMe == nil && applied.position == nil && applied.age == 31)
        #expect(applied.lookingFor == [.chat, .friends])
    }

    private func fields(_ body: JSONValue?) -> [String: JSONValue] {
        if case .object(let fields) = body { return fields }
        return [:]
    }

    @Test func profileTagsAreSentByKey() throws {
        let catalog = ProfileTagCatalog(categories: [
            ProfileTagCategory(
                name: "Hobbies",
                tags: [ProfileTag(key: "hiking", text: "Hiking"), ProfileTag(key: "coffee", text: "Coffee")])
        ])
        // Profiles carry either keys or texts; both match the catalog.
        #expect(["Hiking", "coffee", "Unknown"].map(catalog.key(for:)) == ["hiking", "coffee", "Unknown"])

        let profile = Profile(id: 1, tags: ["hiking", "coffee"])
        var edit = ProfileEdit(profile)
        edit.tags.remove("hiking")
        #expect(fields(edit.update(of: profile))["profileTags"] == .strings(["coffee"]))
        #expect(edit.applied(to: Profile(id: 1)).tags == ["coffee"])

        edit.tags = Set((0...ProfileEdit.maxTags).map(String.init))
        #expect(!edit.isValid)
    }

    @Test func gendersAndPronounsAreSentInTheOrderChosen() throws {
        let profile = Profile(id: 1, genderIDs: [1], pronounIDs: [1])
        var edit = ProfileEdit(profile)
        edit.genderIDs = [4, 1]
        edit.pronounIDs = []
        let sent = fields(edit.update(of: profile))
        #expect(sent["genders"] == .ints([4, 1]) && sent["pronouns"] == .ints([]))
        let applied = edit.applied(to: Profile(id: 1))
        #expect(applied.genderIDs == [4, 1] && applied.pronounIDs.isEmpty)

        edit.genderIDs = Array(1...(ProfileEdit.maxGenders + 1))
        #expect(!edit.isValid)
    }

    @Test func profilePhotosAreUploadedWithACentredSquareThumbnail() async throws {
        let transport = FakeTransport { _ in
            .json(#"{"hash":"h","mediaId":7,"imageSizes":[{"mediaHash":"abc","state":"Pending"}]}"#)
        }
        let photo = try await GrindrAPI(transport: transport).uploadProfilePhoto(Data([1]), width: 400, height: 300)
        #expect(photo == ProfilePhoto(mediaHash: "abc", isPendingReview: true))
        let request = try #require(transport.requests.first)
        #expect(request.method == .post)
        let items = try #require(URLComponents(string: request.path)?.queryItems)
        #expect(items.first { $0.name == "thumbCoords" }?.value == "300,50,350,0", "bottom,left,right,top")
    }

    @Test func theFirstPhotoIsTheMainOne() async throws {
        let transport = FakeTransport { _ in .json("{}") }
        try await GrindrAPI(transport: transport).setProfilePhotos(["a", "b", "c"])
        try await GrindrAPI(transport: transport).setProfilePhotos([])
        let bodies = transport.requests.compactMap(\.jsonObject)
        #expect(bodies.first?["primaryImageHash"] as? String == "a")
        #expect(bodies.first?["secondaryImageHashes"] as? [String] == ["b", "c"])
        #expect(bodies.last?["primaryImageHash"] is NSNull)
        #expect(bodies.last?["secondaryImageHashes"] as? [String] == [])
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
