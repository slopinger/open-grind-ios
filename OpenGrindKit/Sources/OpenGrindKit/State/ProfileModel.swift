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

    /// Loads the profile unless it is loaded already, e.g. when coming back from the chat.
    public func loadIfNeeded() async {
        guard state.needsLoad else { return }
        await load()
    }

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

    /// Reports the profile to Grindr, and blocks it too when `alsoBlock` is set.
    /// Returns whether it is blocked now. Throws only if the report failed: a
    /// failed block becomes ``actionFailure``, so the report isn't sent again.
    @discardableResult
    public func report(_ report: ProfileReport, alsoBlock: Bool) async throws -> Bool {
        try await session.api.report(profileID, report)
        guard alsoBlock else { return false }
        do {
            try await block()
            return true
        } catch {
            actionFailure = Failure(error)
            return false
        }
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
    public var isUploadingPhotos: Bool { uploadingBatches > 0 }
    private var uploadingBatches = 0
    public var actionFailure: Failure?

    /// A blocked profile with what is known about it.
    public struct BlockedEntry: Identifiable, Hashable, Sendable {
        public var id: ProfileID
        public var summary: ProfileSummary?
        public var blockedAt: Date?
    }

    @ObservationIgnored private let api: GrindrAPI
    @ObservationIgnored private let catalogs: CatalogModel
    /// The last change to the photo list; each one waits for the one before.
    @ObservationIgnored private var photoChange: Task<Void, Never>?
    public nonisolated let profileID: ProfileID

    init(api: GrindrAPI, profileID: ProfileID, catalogs: CatalogModel) {
        self.api = api
        self.profileID = profileID
        self.catalogs = catalogs
    }

    public func loadIfNeeded() async {
        guard state.needsLoad else { return }
        await refresh()
    }

    /// Loads your profile, and the catalogs that name its details alongside it.
    public func refresh() async {
        if profile == nil { state = .loading }
        let (api, profileID) = (api, profileID)
        async let loaded = api.profile(profileID)
        await catalogs.loadIfNeeded()
        do {
            var profile = try await loaded
            // Profiles carry tags as keys or texts; keep keys, as edits send them.
            if let tags = catalogs.tags { profile.tags = profile.tags.map(tags.key(for:)) }
            self.profile = profile
            state = .loaded
        } catch {
            if profile == nil { state = .failed(Failure(error)) }
        }
    }

    /// Saves what the edit changed. Throws ``GrindrError/rejectedText`` when
    /// moderation refuses the name or text.
    public func save(_ edit: ProfileEdit) async throws {
        guard let profile else { return }
        guard let update = edit.update(of: profile) else { return }
        try await api.updateProfile(update)
        self.profile = edit.applied(to: profile)
    }

    // MARK: Photos

    /// Grindr allows a main photo and five more.
    public static let maxPhotos = 6

    /// How many more photos fit on your profile.
    public var remainingPhotoSlots: Int { max(Self.maxPhotos - (profile?.photos.count ?? 0), 0) }

    /// Uploads JPEGs and adds them after your other photos. Photos that were
    /// uploaded before one fails are still added.
    public func addPhotos(_ jpegs: [JPEGPhoto]) async {
        uploadingBatches += 1
        defer { uploadingBatches -= 1 }
        var added: [ProfilePhoto] = []
        for jpeg in jpegs.prefix(remainingPhotoSlots) {
            do {
                added.append(try await api.uploadProfilePhoto(jpeg.data, width: jpeg.width, height: jpeg.height))
            } catch {
                actionFailure = Failure(error)
                break
            }
        }
        guard !added.isEmpty else { return }
        // Added to the list as it is now, which may have changed during the upload.
        await changePhotos { [added] in
            guard let current = self.profile?.photos else { return }
            let photos = Array((current + added).prefix(Self.maxPhotos))
            do {
                try await self.api.setProfilePhotos(photos.map(\.mediaHash))
                self.profile?.photos = photos
            } catch {
                self.actionFailure = Failure(error)
            }
        }
    }

    /// Moves a photo to `destination`; position 0 makes it the main photo.
    public func movePhoto(_ photo: ProfilePhoto, to destination: Int) async {
        await changePhotos {
            guard let original = self.profile?.photos, let index = original.firstIndex(of: photo) else { return }
            var photos = original
            photos.remove(at: index)
            photos.insert(photo, at: min(max(destination, 0), photos.count))
            guard photos != original else { return }
            self.profile?.photos = photos
            do {
                try await self.api.setProfilePhotos(photos.map(\.mediaHash))
            } catch {
                self.profile?.photos = original
                self.actionFailure = Failure(error)
            }
        }
    }

    /// Deletes a photo from your profile and from Grindr's servers.
    public func deletePhoto(_ photo: ProfilePhoto) async {
        await changePhotos {
            guard let original = self.profile?.photos, original.contains(photo) else { return }
            let remaining = original.filter { $0 != photo }
            self.profile?.photos = remaining
            do {
                try await self.api.deleteProfilePhotos([photo.mediaHash])
            } catch {
                self.profile?.photos = original
                self.actionFailure = Failure(error)
                return
            }
            // The next photo becomes the main one. The photo is gone either way.
            guard original.first == photo else { return }
            do {
                try await self.api.setProfilePhotos(remaining.map(\.mediaHash))
            } catch {
                self.actionFailure = Failure(error)
            }
        }
    }

    /// Runs changes to the photo list one after another, so each one starts
    /// from the list the one before left, and none overwrites another.
    private func changePhotos(_ change: @escaping @MainActor () async -> Void) async {
        let previous = photoChange
        let task = Task {
            await previous?.value
            await change()
        }
        photoChange = task
        await task.value
    }

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
