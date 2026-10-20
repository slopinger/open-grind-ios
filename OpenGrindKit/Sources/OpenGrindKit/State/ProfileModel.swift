import Foundation
import Observation

/// A profile on screen and what you can do with it.
@MainActor
@Observable
public final class ProfileModel: Identifiable {
    public nonisolated let profileID: ProfileID
    public nonisolated var id: ProfileID { profileID }

    public private(set) var profile: Profile?
    public private(set) var state: LoadState = .idle
    public private(set) var sentTap: TapType?
    /// Set after a tap that turned out mutual.
    public private(set) var isMutualTap = false
    public var actionFailure: Failure?

    @ObservationIgnored private let session: AccountSession
    @ObservationIgnored private var hasRecordedView = false

    /// `preview` is shown while the full profile loads, e.g. the grid tile's data.
    public init(profileID: ProfileID, session: AccountSession, preview: Profile? = nil) {
        self.profileID = profileID
        self.session = session
        profile = preview
    }

    public var isMe: Bool { profileID == session.profileID }

    public func load() async {
        if profile == nil { state = .loading }
        do {
            profile = try await session.api.profile(profileID)
            state = .loaded
            if !hasRecordedView, !isMe {
                hasRecordedView = true
                try? await session.api.recordView(of: profileID)
            }
        } catch {
            state = .failed(Failure(error))
        }
    }

    public func setFavorite(_ isFavorite: Bool) async {
        guard var profile else { return }
        let original = profile
        profile.isFavorite = isFavorite
        self.profile = profile
        do {
            try await session.api.setFavorite(profileID, isFavorite)
            session.favoriteChanged(profileID, isFavorite: isFavorite)
        } catch {
            self.profile = original
            actionFailure = Failure(error)
        }
    }

    public func sendTap(_ type: TapType) async {
        let previous = sentTap
        sentTap = type
        do {
            isMutualTap = try await session.api.sendTap(type, to: profileID)
        } catch {
            sentTap = previous
            actionFailure = Failure(error)
        }
    }

    /// Blocks the profile. It disappears from the grid, inbox and interest lists.
    public func block() async throws {
        try await session.api.block(profileID)
        session.forget(profileID)
    }

    /// Hides the profile from your grid without blocking it.
    public func hide() async throws {
        try await session.api.hide(profileID)
        session.browse.remove(profileID)
    }

    public func report(_ report: ProfileReport) async throws {
        try await session.api.report(profileID, report)
    }

    public var chat: ChatModel {
        session.chat(with: profileID, name: profile?.displayName)
    }
}

/// Your own profile and account lists.
@MainActor
@Observable
public final class MeModel {
    public private(set) var profile: Profile?
    public private(set) var state: LoadState = .idle
    public private(set) var blocked: [BlockedEntry] = []
    public private(set) var blockedState: LoadState = .idle
    public private(set) var genders: [Gender] = []
    public private(set) var pronouns: [Pronoun] = []
    public var actionFailure: Failure?

    /// A blocked profile with what is known about it.
    public struct BlockedEntry: Identifiable, Hashable, Sendable {
        public var id: ProfileID
        public var summary: ProfileSummary?
        public var blockedAt: Date?
    }

    @ObservationIgnored private let api: GrindrAPI
    public nonisolated let profileID: ProfileID

    init(api: GrindrAPI, profileID: ProfileID) {
        self.api = api
        self.profileID = profileID
    }

    public func loadIfNeeded() async {
        guard state == .idle || state.failure != nil else { return }
        await refresh()
    }

    public func refresh() async {
        if profile == nil { state = .loading }
        do {
            profile = try await api.profile(profileID)
            state = .loaded
        } catch {
            if profile == nil { state = .failed(Failure(error)) }
        }
        if genders.isEmpty, let genders = try? await api.genders() { self.genders = genders }
        if pronouns.isEmpty, let pronouns = try? await api.pronouns() { self.pronouns = pronouns }
    }

    /// Saves an edit. Throws ``GrindrError/rejectedText`` when moderation
    /// refuses the name or text.
    public func save(_ edit: ProfileEdit) async throws {
        guard let profile else { return }
        guard let patch = edit.patch(from: ProfileEdit(profile)) else { return }
        try await api.updateProfile(patch)
        self.profile = edit.applied(to: profile)
    }

    public func gender(_ id: Int) -> Gender? { genders.first { $0.id == id } }

    public func pronoun(_ id: Int) -> Pronoun? { pronouns.first { $0.id == id } }

    public func loadBlocked() async {
        if blocked.isEmpty { blockedState = .loading }
        do {
            let entries = try await api.blockedProfiles().sorted {
                ($0.blockedAt ?? .distantPast) > ($1.blockedAt ?? .distantPast)
            }
            let summaries = try? await api.profiles(entries.map(\.id))
            let byID = Dictionary(
                (summaries ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            blocked = entries.map {
                BlockedEntry(id: $0.id, summary: byID[$0.id], blockedAt: $0.blockedAt)
            }
            blockedState = .loaded
        } catch {
            blockedState = .failed(Failure(error))
        }
    }

    public func unblock(_ entry: BlockedEntry) async {
        guard let index = blocked.firstIndex(of: entry) else { return }
        blocked.remove(at: index)
        do {
            try await api.unblock(entry.id)
        } catch {
            blocked.insert(entry, at: min(index, blocked.count))
            actionFailure = Failure(error)
        }
    }
}
