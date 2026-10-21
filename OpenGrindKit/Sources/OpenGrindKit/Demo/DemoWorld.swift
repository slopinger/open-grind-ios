import Foundation

/// A deterministic random generator (SplitMix64), so the demo looks the same
/// on every launch.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// The sample account the demo runs on: profiles nearby, conversations, taps
/// and views, all generated from a fixed seed and kept in memory.
actor DemoWorld {
    static let myProfileID: ProfileID = 10_000
    static let geohash = "u33dc0cppvbz"  // Berlin Mitte

    struct Person {
        var profile: Profile
        var photoSeeds: [String]
    }

    struct Thread {
        var otherID: ProfileID
        var messages: [Message]  // oldest first
        var unread: Int
        var isPinned = false
        var isMuted = false
    }

    private(set) var me: Person
    private var people: [ProfileID: Person] = [:]
    private var order: [ProfileID] = []
    private var threads: [String: Thread] = [:]
    private var taps: [Tap] = []
    private var viewers: [ProfileViewer] = []
    private var blocked: [BlockedProfile] = []
    private var hidden: Set<ProfileID> = []
    private var photoSeeds: [String: String] = [:]
    private var nextMediaID = 1
    private var uploads: [Int: Data] = [:]
    private var uploadedPhotos: [String: Data] = [:]
    private let now: Date

    init(now: Date = .now) {
        self.now = now
        var random = SeededRandom(seed: 0x6F70_656E_6772_6E64)
        me = Self.makeMe(now: now)
        var people: [ProfileID: Person] = [:]
        for (index, seed) in Self.seeds.enumerated() {
            let id = 20_000 + index * 7
            people[id] = Self.makePerson(id: id, seed: seed, index: index, now: now, random: &random)
        }
        // Sorted by distance, as the grid is.
        let order = people.keys.sorted {
            (people[$0]?.profile.distance ?? 0) < (people[$1]?.profile.distance ?? 0)
        }
        var photoSeeds: [String: String] = [:]
        for person in [me] + Array(people.values) {
            for (hash, seed) in zip(person.profile.photos.map(\.mediaHash), person.photoSeeds) {
                photoSeeds[hash] = seed
            }
        }
        self.people = people
        self.order = order
        self.photoSeeds = photoSeeds
        threads = Self.makeThreads(people: people, order: order, now: now)
        (taps, viewers) = Self.makeInterest(people: people, order: order, now: now)
        blocked =
            order.last.map { [BlockedProfile(id: $0, blockedAt: now.addingTimeInterval(-86_400 * 9))] }
            ?? []
    }

    // MARK: Queries

    /// A page of the grid. Exploring another place shows the same people in
    /// another order, so the grid visibly changes.
    func gridPage(filters: BrowseFilters, exploring: String? = nil, page: Int) -> (profiles: [Profile], nextPage: Int?)
    {
        let pageSize = 30
        let blockedIDs = Set(blocked.map(\.id))
        var order = order
        if let exploring, !order.isEmpty {
            let offset = exploring.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % order.count
            order = Array((order[offset...] + order[..<offset]).reversed())
        }
        let matching = order.compactMap { people[$0]?.profile }.filter { profile in
            guard !blockedIDs.contains(profile.id), !hidden.contains(profile.id) else { return false }
            if filters.onlineOnly, !profile.isOnline(at: now) { return false }
            if filters.photosOnly || filters.facePhotosOnly, profile.photos.isEmpty { return false }
            if filters.favoritesOnly, !profile.isFavorite { return false }
            if !filters.positions.isEmpty,
                !(profile.position.map { filters.positions.contains($0) } ?? false)
            {
                return false
            }
            if filters.ages != BrowseFilters.ageBounds, let age = profile.age, !filters.ages.contains(age) {
                return false
            }
            if !filters.lookingFor.isEmpty, filters.lookingFor.isDisjoint(with: profile.lookingFor) {
                return false
            }
            if !filters.tribes.isEmpty, filters.tribes.isDisjoint(with: profile.tribes) { return false }
            if !filters.tags.isEmpty {
                let texts = Set(filters.tags.map(Self.tagCatalog.text(for:)))
                if texts.isDisjoint(with: profile.tags) { return false }
            }
            return true
        }
        let start = (page - 1) * pageSize
        guard start < matching.count else { return ([], nil) }
        let end = min(start + pageSize, matching.count)
        return (Array(matching[start..<end]), end < matching.count ? page + 1 : nil)
    }

    func profile(_ id: ProfileID) -> Profile? {
        if id == me.profile.id { return me.profile }
        guard !blocked.contains(where: { $0.id == id }) else { return nil }
        return people[id]?.profile
    }

    /// A profile whether or not you blocked it, as `POST /v3/profiles` answers.
    func summary(_ id: ProfileID) -> Profile? {
        id == me.profile.id ? me.profile : people[id]?.profile
    }

    func conversations() -> [(id: String, thread: Thread, profile: Profile)] {
        threads.compactMap { id, thread in
            people[thread.otherID].map { (id, thread, $0.profile) }
        }
        .filter { !$0.thread.messages.isEmpty }
        .sorted {
            ($0.thread.messages.last?.date ?? .distantPast)
                > ($1.thread.messages.last?.date ?? .distantPast)
        }
    }

    func thread(_ conversationID: String) -> Thread? { threads[conversationID] }

    func receivedTaps() -> [Tap] { taps }

    func profileViewers() -> [ProfileViewer] { viewers }

    func blockedProfiles() -> [BlockedProfile] { blocked }

    func photoSeed(for hash: String) -> String? { photoSeeds[hash] }

    func uploadedPhoto(_ hash: String) -> Data? { uploadedPhotos[hash] }

    // MARK: Changes

    /// Applies a `PATCH /v4/me/profile` body.
    func updateMe(_ json: Data) {
        guard let patch = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
            return
        }
        var profile = me.profile
        func has(_ key: String) -> Bool { patch[key] != nil }
        if has("displayName") { profile.displayName = patch["displayName"] as? String }
        if has("aboutMe") { profile.aboutMe = patch["aboutMe"] as? String }
        if has("age") { profile.age = Self.int(patch["age"]) }
        if let value = Self.bool(patch["showAge"]) { profile.showsAge = value }
        if let value = Self.bool(patch["showDistance"]) { profile.showsDistance = value }
        if has("height") { profile.height = Self.double(patch["height"]) }
        if has("weight") { profile.weight = Self.double(patch["weight"]) }
        if has("sexualPosition") {
            profile.position = SexualPosition.known(Self.int(patch["sexualPosition"]))
        }
        if has("bodyType") { profile.bodyType = BodyType.known(Self.int(patch["bodyType"])) }
        if has("ethnicity") { profile.ethnicity = Ethnicity.known(Self.int(patch["ethnicity"])) }
        if has("relationshipStatus") {
            profile.relationshipStatus = RelationshipStatus.known(Self.int(patch["relationshipStatus"]))
        }
        if let value = Self.ints(patch["lookingFor"]) { profile.lookingFor = LookingFor.known(value) }
        if let value = Self.ints(patch["meetAt"]) { profile.meetAt = MeetAt.known(value) }
        if let value = Self.ints(patch["grindrTribes"]) { profile.tribes = Tribe.known(value) }
        if has("nsfw") { profile.acceptsNSFWPics = AcceptsNSFWPics.known(Self.int(patch["nsfw"])) }
        if has("hivStatus") { profile.hivStatus = HIVStatus.known(Self.int(patch["hivStatus"])) }
        if let value = Self.ints(patch["sexualHealth"]) {
            profile.sexualHealth = SexualHealthPractice.known(value)
        }
        if let value = Self.ints(patch["vaccines"]) { profile.vaccines = Vaccine.known(value) }
        if let value = Self.bool(patch["showPosition"]) { profile.showsPosition = value }
        if let value = Self.bool(patch["showTribes"]) { profile.showsTribes = value }
        if let value = Self.ints(patch["genders"]) { profile.genderIDs = value }
        if let value = Self.ints(patch["pronouns"]) { profile.pronounIDs = value }
        if let keys = patch["profileTags"] as? [String] {
            profile.tags = keys.map(Self.tagCatalog.text(for:))
        }
        if has("lastTestedDate") {
            profile.lastTested = Self.double(patch["lastTestedDate"]).map {
                Date(milliseconds: Int64($0))
            }
        }
        me.profile = profile
    }

    static func int(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? NSNumber)?.intValue
    }

    static func double(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    static func bool(_ value: Any?) -> Bool? {
        (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    static func ints(_ value: Any?) -> [Int]? {
        (value as? [Any])?.compactMap(int)
    }

    func setFavorite(_ id: ProfileID, _ isFavorite: Bool) {
        people[id]?.profile.isFavorite = isFavorite
    }

    func block(_ id: ProfileID) {
        guard !blocked.contains(where: { $0.id == id }) else { return }
        blocked.insert(BlockedProfile(id: id, blockedAt: .now), at: 0)
        threads[Conversation.id(between: DemoWorld.myProfileID, and: id)] = nil
        taps.removeAll { $0.profileID == id }
        viewers.removeAll { $0.profileID == id }
    }

    func unblock(_ id: ProfileID) {
        blocked.removeAll { $0.id == id }
    }

    func hide(_ id: ProfileID) {
        hidden.insert(id)
    }

    /// Records a `POST /v4/chat/message/send` body and returns the message as
    /// the server would.
    func send(_ json: Data) -> Message? {
        guard let request = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
            let type = request["type"] as? String,
            let target = request["target"] as? [String: Any], let id = Self.int(target["targetId"]),
            let body = request["body"] as? [String: Any]
        else { return nil }
        let conversationID = Conversation.id(between: DemoWorld.myProfileID, and: id)
        let content: Message.Content
        switch type {
        case "Text":
            guard let text = body["text"] as? String else { return nil }
            content = .text(text)
        case "Image":
            guard let mediaID = Self.int(body["mediaId"]), let url = uploadURL(mediaID) else {
                return nil
            }
            content = .image(url: url, width: 600, height: 800)
        case "Location":
            guard let lat = Self.double(body["lat"]), let lon = Self.double(body["lon"]) else {
                return nil
            }
            content = .location(latitude: lat, longitude: lon)
        default:
            return nil
        }
        let message = Message(
            id: "demo-\(UUID().uuidString.lowercased())", conversationID: conversationID,
            senderID: DemoWorld.myProfileID, date: .now, content: content)
        threads[conversationID, default: Thread(otherID: id, messages: [], unread: 0)].messages.append(
            message)
        return message
    }

    /// The reply a demo profile sends a little while after you write.
    func reply(in conversationID: String) -> Message? {
        guard let thread = threads[conversationID], let last = thread.messages.last,
            last.senderID == DemoWorld.myProfileID
        else { return nil }
        let replies = [
            "Hey! Thanks for the message 😊", "Haha, love that. What are you up to tonight?",
            "Nice to meet you! I'm just around the corner.", "Sounds good to me. Coffee sometime?",
            "Ha, you made my day 😄", "Just got back from the gym, give me a minute.",
        ]
        let text = replies[thread.messages.count % replies.count]
        let message = Message(
            id: "demo-\(UUID().uuidString.lowercased())", conversationID: conversationID,
            senderID: thread.otherID,
            date: .now, content: .text(text))
        threads[conversationID]?.messages.append(message)
        return message
    }

    func markRead(_ conversationID: String) {
        threads[conversationID]?.unread = 0
    }

    func setPinned(_ conversationID: String, _ isPinned: Bool) {
        threads[conversationID]?.isPinned = isPinned
    }

    func setMuted(_ conversationID: String, _ isMuted: Bool) {
        threads[conversationID]?.isMuted = isMuted
    }

    func deleteConversation(_ conversationID: String) {
        threads[conversationID] = nil
    }

    func unsend(_ messageID: String, in conversationID: String) {
        guard let index = threads[conversationID]?.messages.firstIndex(where: { $0.id == messageID })
        else { return }
        threads[conversationID]?.messages[index].content = .unsent
    }

    func deleteMessage(_ messageID: String, in conversationID: String) {
        threads[conversationID]?.messages.removeAll { $0.id == messageID }
    }

    func react(to messageID: String, in conversationID: String) -> Message? {
        guard let index = threads[conversationID]?.messages.firstIndex(where: { $0.id == messageID })
        else {
            return nil
        }
        threads[conversationID]?.messages[index].reactions.append(
            MessageReaction(profileID: DemoWorld.myProfileID, type: MessageReaction.heart))
        return threads[conversationID]?.messages[index]
    }

    /// Applies `PUT /v3/me/profile/images`: photos you uploaded stay in review.
    func setMyPhotos(_ hashes: [String]) {
        let known = Dictionary(me.profile.photos.map { ($0.mediaHash, $0) }, uniquingKeysWith: { first, _ in first })
        me.profile.photos = hashes.prefix(6).map {
            known[$0] ?? ProfilePhoto(mediaHash: $0, isPendingReview: uploadedPhotos[$0] != nil)
        }
    }

    func deleteMyPhotos(_ hashes: Set<String>) {
        me.profile.photos.removeAll { hashes.contains($0.mediaHash) }
        for hash in hashes { uploadedPhotos[hash] = nil }
    }

    func upload(_ data: Data) -> (mediaID: Int, url: URL, hash: String) {
        let mediaID = nextMediaID
        nextMediaID += 1
        uploads[mediaID] = data
        let hash = String(repeating: "f", count: 32) + String(format: "%08x", mediaID)
        uploadedPhotos[hash] = data
        return (mediaID, MediaURL.profileImage(hash, size: .full), hash)
    }

    private func uploadURL(_ mediaID: Int) -> URL? {
        guard uploads[mediaID] != nil else { return nil }
        return MediaURL.profileImage(
            String(repeating: "f", count: 32) + String(format: "%08x", mediaID), size: .full)
    }

    // MARK: Generation

    private struct Seed {
        var name: String
        var bio: String
    }

    private static let seeds: [Seed] = [
        Seed(name: "Max", bio: "Coffee first, everything else later. New to the neighborhood."),
        Seed(name: "Jonas", bio: "Climber, cook, occasional runner. Ask me about my sourdough."),
        Seed(name: "Theo", bio: "Architect by day, synth nerd by night."),
        Seed(name: "Luca", bio: "Here for a short while. Show me your favorite spots!"),
        Seed(name: "Ben", bio: "Dog dad 🐶 Books, hikes and long breakfasts."),
        Seed(name: "Noah", bio: "Nurse. Night shifts, so I reply at weird hours."),
        Seed(name: "Elias", bio: "Film photography and flea markets."),
        Seed(name: "Paul", bio: "Let's grab a drink and see where it goes."),
        Seed(name: "Finn", bio: "Swimmer. Lake > pool. Always up for a picnic."),
        Seed(name: "Leon", bio: "Software developer, board game collector."),
        Seed(name: "Mateo", bio: "Salsa dancer and terrible singer."),
        Seed(name: "Oskar", bio: "Just moved from Hamburg. Show me Berlin."),
        Seed(name: "Jamal", bio: "Chef. I'll judge your fridge, lovingly."),
        Seed(name: "Kai", bio: "Gym, gaming, good vibes."),
        Seed(name: "Ravi", bio: "PhD student. Will talk about birds for hours."),
        Seed(name: "Tom", bio: "Outdoorsy. Cyclist. Sunday market regular."),
        Seed(name: "Samuel", bio: "Teacher. Bad puns are my love language."),
        Seed(name: "Adrian", bio: "Vinyl, wine, late conversations."),
        Seed(name: "Moritz", bio: "Looking for a gym buddy and maybe more."),
        Seed(name: "Daniel", bio: "Visiting for the conference. Recommendations welcome."),
        Seed(name: "Hugo", bio: "Plants everywhere. Yes, I name them."),
        Seed(name: "Emil", bio: "Barista. I'll remember your order."),
        Seed(name: "Yusuf", bio: "Photographer and night owl."),
        Seed(name: "Liam", bio: "Rugby, beer, and a soft spot for musicals."),
        Seed(name: "Niklas", bio: "Doing my best. Mostly succeeding."),
        Seed(name: "Arjun", bio: "Engineer who cooks too much dal."),
        Seed(name: "Felix", bio: "Cat person. Don't hold it against me."),
        Seed(name: "Marco", bio: "Italian, so yes, I have opinions about pasta."),
        Seed(name: "Jakob", bio: "Musician. Cello mostly, kazoo occasionally."),
        Seed(name: "Chris", bio: "Runner. Marathon training, wish me luck."),
        Seed(name: "Ivan", bio: "Quiet at first, then I don't stop talking."),
        Seed(name: "Sven", bio: "Sauna enthusiast. Northern charm."),
        Seed(name: "Tariq", bio: "Designer. Fonts make me emotional."),
        Seed(name: "Lars", bio: "Weekend sailor."),
        Seed(name: "Pedro", bio: "Here for chats and coffee."),
        Seed(name: "Anton", bio: "Med student. Sleep is a myth."),
        Seed(name: "Julian", bio: "Gardener, baker, cyclist."),
        Seed(name: "Kenji", bio: "Ramen hunter. I know every shop in town."),
        Seed(name: "Viktor", bio: "Historian. Ask me something."),
        Seed(name: "Omar", bio: "Traveling through. Say hi!"),
        Seed(name: "Robin", bio: "Theatre kid who never grew out of it."),
        Seed(name: "Simon", bio: "Kind, curious, a bit chaotic."),
    ]

    private static func photoHash(for seed: String) -> String {
        var random = SeededRandom(
            seed: UInt64(truncatingIfNeeded: seed.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }))
        return (0..<5).map { _ in String(format: "%08x", UInt32(truncatingIfNeeded: random.next())) }
            .joined()
    }

    private static func makeMe(now: Date) -> Person {
        let seeds = ["me-1", "me-2"]
        let profile = Profile(
            id: myProfileID, displayName: "Alex", aboutMe: "Trying out Open Grind on iPhone. Say hi 👋",
            age: 31,
            distance: 0, onlineUntil: now.addingTimeInterval(600),
            photos: seeds.map { ProfilePhoto(mediaHash: photoHash(for: $0)) }, height: 180,
            weight: 75_000,
            position: .versatile, bodyType: .toned, relationshipStatus: .single, tribes: [.geek, .otter],
            lookingFor: [.chat, .dates, .friends], meetAt: [.coffeeShop, .bar],
            acceptsNSFWPics: .notAtFirst,
            hivStatus: .negativeOnPrEP, lastTested: now.addingTimeInterval(-86_400 * 40),
            sexualHealth: [.prep],
            vaccines: [.monkeypox, .covid19], genderIDs: [1], pronounIDs: [1])
        return Person(profile: profile, photoSeeds: seeds)
    }

    private static func makePerson(
        id: ProfileID, seed: Seed, index: Int, now: Date, random: inout SeededRandom
    ) -> Person {
        let photoCount = index % 9 == 8 ? 0 : Int.random(in: 1...4, using: &random)
        let seeds = (0..<photoCount).map { "\(seed.name.lowercased())-\(id)-\($0)" }
        let isOnline = index % 3 != 2
        let distance = Double(index) * 140 + Double.random(in: 20...140, using: &random)
        var profile = Profile(
            id: id, displayName: index % 11 == 10 ? nil : seed.name, aboutMe: seed.bio,
            age: Int.random(in: 21...52, using: &random), showsAge: index % 7 != 6, distance: distance,
            isDistanceApproximate: index % 5 == 4,
            onlineUntil: isOnline
                ? now.addingTimeInterval(Double.random(in: 120...900, using: &random)) : nil,
            lastSeen: now.addingTimeInterval(
                isOnline ? -60 : -Double.random(in: 900...86_400 * 3, using: &random)),
            photos: seeds.map { ProfilePhoto(mediaHash: photoHash(for: $0)) },
            height: Double.random(in: 165...198, using: &random).rounded(),
            weight: (Double.random(in: 60...105, using: &random) * 1000).rounded())
        profile.position = SexualPosition.allCases.randomElement(using: &random)
        profile.bodyType = BodyType.allCases.randomElement(using: &random)
        profile.ethnicity = index % 4 == 0 ? nil : Ethnicity.allCases.randomElement(using: &random)
        profile.relationshipStatus = [RelationshipStatus.single, .single, .dating, .openRelationship]
            .randomElement(
                using: &random)
        profile.tribes = Array(
            Tribe.allCases.shuffled(using: &random).prefix(Int.random(in: 0...2, using: &random)))
        profile.lookingFor = Array(
            LookingFor.allCases.shuffled(using: &random).prefix(Int.random(in: 1...3, using: &random)))
        profile.meetAt = Array(
            MeetAt.allCases.shuffled(using: &random).prefix(Int.random(in: 0...2, using: &random)))
        profile.acceptsNSFWPics = AcceptsNSFWPics.allCases.randomElement(using: &random)
        profile.hivStatus = index % 3 == 0 ? nil : HIVStatus.settableCases.randomElement(using: &random)
        profile.vaccines = Array(Vaccine.allCases.prefix(index % 4))
        profile.isFavorite = index % 10 == 3
        profile.isNew = index % 8 == 5
        profile.isVisiting = seed.bio.contains("Visiting") || seed.bio.contains("Traveling")
        profile.genderIDs = [1]
        profile.instagram = index % 6 == 1 ? seed.name.lowercased() + ".berlin" : nil
        profile.tags = Array(
            tagCatalog.tags(matching: "").shuffled(using: &random).prefix(Int.random(in: 0...4, using: &random))
        ).map(\.text)
        return Person(profile: profile, photoSeeds: seeds)
    }

    /// The tags the demo offers in its filters and puts on its profiles.
    static let tagCatalog = ProfileTagCatalog(categories: [
        ProfileTagCategory(
            name: "Interests",
            tags: [
                ProfileTag(key: "hiking", text: "Hiking"), ProfileTag(key: "coffee", text: "Coffee"),
                ProfileTag(key: "gaming", text: "Gaming"), ProfileTag(key: "music", text: "Music"),
                ProfileTag(key: "cooking", text: "Cooking"), ProfileTag(key: "gym", text: "Gym"),
                ProfileTag(key: "travel", text: "Travel"), ProfileTag(key: "art", text: "Art"),
            ]),
        ProfileTagCategory(
            name: "Personality",
            tags: [
                ProfileTag(key: "funny", text: "Funny"), ProfileTag(key: "nerd", text: "Nerd"),
                ProfileTag(key: "chill", text: "Chill"), ProfileTag(key: "romantic", text: "Romantic"),
            ]),
    ])

    private static func makeThreads(
        people: [ProfileID: Person], order: [ProfileID], now: Date
    ) -> [String: Thread] {
        var threads: [String: Thread] = [:]
        let scripts: [[(fromMe: Bool, text: String, minutesAgo: Double)]] = [
            [
                (false, "Hey there 👋", 52), (true, "Hi! How's your evening going?", 50),
                (false, "Pretty chill. Just made pasta 🍝", 6), (false, "You?", 5),
            ],
            [
                (true, "Loved your photo from the lake!", 300),
                (false, "Thanks! It's my favorite spot", 280), (false, "Want to go sometime?", 279),
            ],
            [
                (false, "Are you going to the market on Sunday?", 1500),
                (true, "Probably! Around 11?", 1440), (false, "Perfect, see you there", 1430),
            ],
            [(false, "Hi! New here, any recommendations for a good coffee place?", 30)],
            [(true, "Haha that's amazing", 4320), (false, "Right?! 😂", 4300)],
            [(false, "Nice profile 😊", 15000)],
        ]
        let partners = Array(order.prefix(12)).enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        for (script, partner) in zip(scripts, partners) {
            let conversationID = Conversation.id(between: DemoWorld.myProfileID, and: partner)
            var messages: [Message] = []
            for (index, line) in script.enumerated() {
                messages.append(
                    Message(
                        id: "demo-\(partner)-\(index)", conversationID: conversationID,
                        senderID: line.fromMe ? DemoWorld.myProfileID : partner,
                        date: now.addingTimeInterval(-line.minutesAgo * 60), content: .text(line.text)))
            }
            let unread = script.reversed().prefix { !$0.fromMe }.count
            let isFirst = threads.isEmpty
            threads[conversationID] = Thread(
                otherID: partner, messages: messages, unread: script.count > 3 || isFirst ? unread : 0,
                isPinned: partners.firstIndex(of: partner) == 2)
        }
        return threads
    }

    private static func makeInterest(
        people: [ProfileID: Person], order: [ProfileID], now: Date
    ) -> ([Tap], [ProfileViewer]) {
        let tappers = order.dropFirst(3).enumerated().filter { $0.offset % 4 == 1 }.prefix(6).map(
            \.element)
        let taps = tappers.enumerated().compactMap { index, id -> Tap? in
            guard let profile = people[id]?.profile else { return nil }
            return Tap(
                profileID: id, displayName: profile.displayName, photoHash: profile.primaryPhoto?.mediaHash,
                distance: profile.distance, date: now.addingTimeInterval(-Double(index * index + 1) * 1800),
                type: TapType(rawValue: index % 3), isMutual: index == 1, onlineUntil: profile.onlineUntil,
                isFavorite: profile.isFavorite)
        }
        let viewerIDs = order.dropFirst(5).enumerated().filter { $0.offset % 3 == 0 }.prefix(9).map(
            \.element)
        let viewers = viewerIDs.enumerated().compactMap { index, id -> ProfileViewer? in
            guard let profile = people[id]?.profile else { return nil }
            return ProfileViewer(
                profileID: id, displayName: profile.displayName, photoHash: profile.primaryPhoto?.mediaHash,
                distance: profile.distance, lastViewed: now.addingTimeInterval(-Double(index + 1) * 2700),
                viewCount: index % 4 + 1, onlineUntil: profile.onlineUntil, isFavorite: profile.isFavorite)
        }
        return (taps, viewers)
    }
}
