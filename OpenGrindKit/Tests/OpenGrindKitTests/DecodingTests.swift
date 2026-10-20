import Foundation
import Testing

@testable import OpenGrindKit

/// Decoding of API responses, with payloads shaped like Open Grind's API
/// reference and its test fixtures.
struct DecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSON.decode(type, from: Data(json.utf8))
    }

    @Test func cascadeKeepsProfilesAndSkipsEverythingElse() throws {
        let page = try decode(
            CascadePage.self,
            """
            {"items":[
              {"type":"full_profile_v1","data":{"profileId":1,"displayName":"Ada","distanceMeters":1234.5,
               "primaryImageUrl":"https://cdns.grindr.com/images/thumb/320x320/abc","onlineUntil":4102444800000,
               "sexualPosition":3,"unreadCount":2,"favorite":true,"bodyType":9999}},
              {"type":"advert_v1","data":{"cascadePlacementName":"x"}},
              {"type":"some_future_item_v1","data":{"anything":true}},
              {"type":"partial_profile_v1","data":{"profileId":"2","upsellItemType":"xtra"}},
              {"type":"full_profile_v1","data":{"displayName":"no id"}},
              {"type":"full_profile_v1","data":{"profileId":1,"displayName":"duplicate"}}
            ],"nextPage":2,"shuffled":false}
            """)
        #expect(page.profiles.map(\.id) == [1, 2])
        #expect(page.nextPage == 2)
        let ada = try #require(page.profiles.first)
        #expect(ada.displayName == "Ada")
        #expect(ada.distance == 1234.5)
        #expect(ada.position == .versatile)
        #expect(ada.unreadCount == 2)
        #expect(ada.isFavorite)
        #expect(ada.isOnline(at: Date(timeIntervalSince1970: 0)))
        #expect(ada.photoURL?.absoluteString == "https://cdns.grindr.com/images/thumb/320x320/abc")
        #expect(page.profiles[1].isLocked)
    }

    @Test func mediaFromUnknownHostsIsNeverLoaded() throws {
        let page = try decode(
            CascadePage.self,
            #"{"items":[{"type":"full_profile_v1","data":{"profileId":1,"primaryImageUrl":"https://evil.example/a"}}]}"#
        )
        #expect(page.profiles.first?.photoURL == nil)
        #expect(MediaURL.validated("http://cdns.grindr.com/images/x") == nil)
        #expect(MediaURL.validated("https://d1.cloudfront.net/x") != nil)
    }

    @Test func profileGendersSkipHiddenOnesAndPutTheMainOnesFirst() throws {
        let json = Data(
            #"""
            [{"genderId":9,"gender":"Queer","displayGroup":2,"sortProfile":1},
             {"genderId":2,"gender":"Woman","displayGroup":1,"excludeOnProfileSelection":[1]},
             {"genderId":12,"gender":"Hidden","displayGroup":0},
             {"genderId":1,"gender":"Man","displayGroup":1,"excludeOnProfileSelection":[2]},
             {"genderId":8,"gender":"Genderqueer","displayGroup":2,"sortProfile":0}]
            """#.utf8)
        let genders = try JSONDecoder().decode([Gender].self, from: json)
        #expect(Gender.profileOptions(genders).map(\.id) == [1, 2, 8, 9])
        #expect(genders.first { $0.id == 1 }?.excludedOnProfile == [2])
    }

    @Test func tagCatalogUsesTheFirstLanguageAndSkipsBrokenEntries() throws {
        let catalog = try decode(
            ProfileTagCatalog.self,
            """
            [{"language":"de","categoryCollection":[
              {"text":"Hobbys","possessiveText":null,"tags":[
                {"tagId":1,"key":"hiking","text":"Wandern"},{"tagId":2,"text":"no key"},
                {"tagId":3,"key":"coffee","text":"Kaffee"}]},
              {"text":"Leer","tags":[]}]},
             {"language":"en","categoryCollection":[
              {"text":"Hobbies","tags":[{"tagId":1,"key":"hiking","text":"Hiking"}]}]}]
            """)
        #expect(catalog.categories.map(\.name) == ["Hobbys"])
        #expect(catalog.categories.first?.tags.map(\.key) == ["hiking", "coffee"])
        #expect(catalog.text(forKey: "coffee") == "Kaffee")
        #expect(catalog.tags(matching: "wand").map(\.key) == ["hiking"])
    }

    @Test func gaymojiURLsAndLabels() {
        #expect(
            MediaURL.gaymoji("gaymoji/Man_with_beard%2C.png")?.absoluteString
                == "https://cdns.grindr.com/grindr/chat/gaymoji/Man_with_beard%252C.png")
        #expect(
            MediaURL.gaymoji("gaymoji/1_2_Yass.png")?.absoluteString
                == "https://cdns.grindr.com/grindr/chat/gaymoji/1_2_Yass.png")
        #expect(MediaURL.gaymoji("gaymoji/") == nil)
        #expect(MediaURL.gaymojiLabel("gaymoji/1_2_Yass.png") == "Yass")
        #expect(MediaURL.gaymojiLabel("gaymoji/a_Hot_Dog.png") == "Hot Dog")
    }

    @Test func profileDecodesFieldsAndToleratesUnknownValues() throws {
        let profile = try decode(
            Profile.self,
            """
            {"profileId":"42","displayName":"Ben","aboutMe":"Hi","age":30,"showAge":true,"distance":250,
             "showDistance":true,"medias":[{"mediaHash":"aaa","type":1,"state":1},{"mediaHash":"bbb","state":0}],
             "profileImageMediaHash":"aaa","height":180,"weight":75000,"sexualPosition":42,"bodyType":4,
             "grindrTribes":[1,99,12],"lookingFor":[2,7],"hivStatus":5,"lastTestedDate":1700000000000,
             "socialNetworks":{"instagram":{"userId":"ben"}},"isFavorite":true,"tapType":3,"vaccines":null,
             "identity":{"whatever":[1,2]}}
            """)
        #expect(profile.id == 42)
        #expect(
            profile.photos == [
                ProfilePhoto(mediaHash: "aaa"), ProfilePhoto(mediaHash: "bbb", isPendingReview: true),
            ])
        #expect(profile.position == nil)
        #expect(profile.bodyType == .muscular)
        #expect(profile.tribes == [.bear, .twink])
        #expect(profile.lookingFor == [.chat, .hookups])
        #expect(profile.hivStatus == .preferToDiscuss)
        #expect(profile.lastTested == Date(milliseconds: 1_700_000_000_000))
        #expect(profile.instagram == "ben")
        #expect(profile.receivedTap == nil)
        #expect(profile.vaccines.isEmpty)
        #expect(profile.showsTribes)
    }

    @Test func blockedProfileStubsAreRecognized() throws {
        let stub = try decode(
            Profile.self, #"{"profileId":7,"displayName":"4","showAge":false,"medias":[]}"#)
        #expect(stub.isUnavailableStub)
        let real = try decode(Profile.self, #"{"profileId":7,"displayName":"4","age":44}"#)
        #expect(!real.isUnavailableStub)
    }

    @Test func inboxDecodesConversationsAndDropsUnknownEntries() throws {
        let page = try decode(
            InboxPage.self,
            """
            {"entries":[
              {"type":"full_conversation_v1","data":{"conversationId":"1:2","name":"Ada",
               "participants":[{"profileId":2,"primaryMediaHash":"abc","distanceMetres":12.5,"position":1}],
               "lastActivityTimestamp":1700000000000,"unreadCount":3,
               "preview":{"messageId":"m1","type":"Text","text":"hey","senderId":"2"},"muted":true,"pinned":false}},
              {"type":"group_conversation_v9","data":{}},
              {"type":"partial_conversation_v1","data":{"conversationId":"1:3","name":"","participants":[],
               "lastActivityTimestamp":1700000000001,"unreadCount":0,"preview":null}}
            ],"nextPage":null}
            """)
        #expect(page.conversations.map(\.id) == ["1:2", "1:3"])
        let first = page.conversations[0]
        #expect(first.participant?.id == 2)
        #expect(first.participant?.position == .top)
        #expect(first.preview == MessagePreview(messageID: "m1", kind: .text, text: "hey", senderID: 2))
        #expect(first.isMuted)
        #expect(page.conversations[1].isLocked)
        #expect(page.conversations[1].otherProfileID(me: 1) == 3)
    }

    @Test func messagesDecodeEachContentType() throws {
        let page = try decode(
            MessagePage.self,
            """
            {"lastReadTimestamp":1700000000000,"profile":{"profileId":2,"name":"Ada","mediaHash":null,
             "onlineUntil":null,"distance":10,"showDistance":false},
             "messages":[
              {"messageId":"5","conversationId":"1:2","senderId":2,"timestamp":5,"unsent":false,"reactions":[],
               "type":"Text","body":{"text":"hello"}},
              {"messageId":"4","conversationId":"1:2","senderId":1,"timestamp":4,"unsent":false,
               "reactions":[{"profileId":2,"reactionType":1}],"type":"Image",
               "body":{"mediaId":9,"url":"https://cdns.grindr.com/chat/x","width":10,"height":20,
                       "imageHash":"x","takenOnGrindr":false,"createdAt":null}},
              {"messageId":"3","conversationId":"1:2","senderId":2,"timestamp":3,"unsent":true,"reactions":[],
               "type":"Text","body":null},
              {"messageId":"2","conversationId":"1:2","senderId":2,"timestamp":2,"unsent":false,"reactions":[],
               "type":"Location","body":{"lat":52.5,"lon":13.4}},
              {"messageId":"1","conversationId":"1:2","senderId":2,"timestamp":1,"unsent":false,"reactions":[],
               "type":"VideoCall","body":{"result":"missed"}},
              {"messageId":"0","conversationId":"1:2","type":"Text"}
            ]}
            """)
        #expect(page.messages.map(\.id) == ["5", "4", "3", "2", "1"])
        #expect(page.messages[0].content == .text("hello"))
        #expect(
            page.messages[1].content
                == .image(url: URL(string: "https://cdns.grindr.com/chat/x")!, width: 10, height: 20))
        #expect(page.messages[1].reactions == [MessageReaction(profileID: 2, type: 1)])
        #expect(page.messages[2].content == .unsent)
        #expect(page.messages[3].content == .location(latitude: 52.5, longitude: 13.4))
        #expect(page.messages[4].content == .unsupported(.videoCall))
        #expect(page.nextPageKey == "1")
        #expect(page.profile?.distance == nil, "the profile hides its distance")
    }

    @Test func realtimeEventsDecode() throws {
        func event(_ type: String, _ payload: String) -> RealtimeEvent {
            RealtimeEvent.decode(
                type: type,
                json: Data(#"{"type":"\#(type)","notificationId":null,"payload":\#(payload)}"#.utf8))
        }
        #expect(
            event(
                "chat.v1.conversation_read", #"{"conversationId":"1:2","profileId":"2","timestamp":1000}"#)
                == .conversationRead(conversationID: "1:2", profileID: 2, date: Date(milliseconds: 1000)))
        #expect(
            event("chat.v1.typing_status", #"{"conversationId":"1:2","profileId":2,"status":"Typing"}"#)
                == .typing(conversationID: "1:2", profileID: 2, isTyping: true))
        #expect(
            event("chat.v1.conversation.delete", #"{"conversationIds":["1:2"]}"#)
                == .conversationsDeleted(["1:2"]))
        guard
            case .tapReceived(let tap) = event(
                "tap.v2.tap_sent",
                #"{"timestamp":1,"senderId":2,"recipientId":1,"tapType":1,"senderProfileImageHash":null,"senderDisplayName":"Ada","isMutual":true}"#
            )
        else {
            Issue.record("expected a tap")
            return
        }
        #expect(tap.profileID == 2 && tap.type == .hot && tap.isMutual && tap.displayName == "Ada")
        #expect(
            event("chat.v1.message_sent", #"{"broken":true}"#) == .other(type: "chat.v1.message_sent"))
        #expect(event("something.new", "{}") == .other(type: "something.new"))
    }

    @Test func retractMessagesNameTheirTarget() throws {
        let message = try decode(
            Message.self,
            #"{"messageId":"9","conversationId":"1:2","senderId":2,"timestamp":9,"type":"Retract","body":{"targetMessageId":"5"}}"#
        )
        #expect(message.retractedMessageID == "5")
        #expect(message.content.kind == .retract)
    }

    @Test func errorsAreClassifiedFromTheResponse() {
        #expect(GrindrError.from(.json("{}", status: 401)) == .unauthorized)
        #expect(GrindrError.from(.json("{}", status: 429)) == .rateLimited)
        #expect(
            GrindrError.from(.json(#"{"type":"urn:gr:err:unauthorized_action"}"#, status: 403))
                == .unavailable)
        #expect(
            GrindrError.from(.json(#"{"type":"urn:gr:err:hit_banned_terms"}"#, status: 400))
                == .rejectedText)
        #expect(
            GrindrError.from(.json(#"{"type":"urn:gr:err:tiered_feature"}"#, status: 403))
                == .requiresSubscription)
        #expect(
            GrindrError.from(.json(#"{"code":27,"message":"nope"}"#, status: 400))
                == .server(status: 400, code: "27", message: "nope"))
        #expect(GrindrError.from(.json("<html>", status: 503)).isTransient)
        #expect(
            GrindrError.from(.json("CAS-4001", status: 403)) == .requiresSubscription,
            "exploring without a subscription")
        #expect(GrindrError.from(.json(#"{"code":"CAS-4001"}"#, status: 400)) == .requiresSubscription)
        #expect(
            GrindrError.from(.json("CAS-1234", status: 400)) == .server(status: 400, code: "CAS-1234", message: nil))
    }

    @Test func credentialsNameTheirProfile() {
        #expect(profileID(fromCredentials: #"{"email":"a","profile_id":"42","auth_token":"x"}"#) == 42)
        #expect(profileID(fromCredentials: #"{"email":"a","auth_token":"x"}"#) == nil)
        #expect(profileID(fromCredentials: "garbage") == nil)
    }
}
