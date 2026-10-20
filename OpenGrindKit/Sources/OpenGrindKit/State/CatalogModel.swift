import Foundation
import Observation

/// The lists profile details refer to: genders, pronouns and tags. Each is
/// loaded once per session.
@MainActor
@Observable
public final class CatalogModel {
    public private(set) var genders: [Gender] = []
    public private(set) var pronouns: [Pronoun] = []
    public private(set) var tags: ProfileTagCatalog?
    /// Tags are chosen from the catalog, so screens show why it is missing.
    public private(set) var tagsState: LoadState = .idle

    @ObservationIgnored private let api: GrindrAPI
    /// Lets callers that arrive while the tags load wait for the same request.
    @ObservationIgnored private var tagsTask: Task<Void, Never>?

    init(api: GrindrAPI) {
        self.api = api
    }

    /// Loads whatever is still missing, all at once.
    public func loadIfNeeded() async {
        async let genders: Void = loadGenders()
        async let pronouns: Void = loadPronouns()
        async let tags: Void = loadTags()
        _ = await (genders, pronouns, tags)
    }

    /// Loads the tag catalog unless it is loaded, or waits for the load in progress.
    public func loadTags() async {
        guard tags == nil else { return }
        if let tagsTask { return await tagsTask.value }
        let task = Task {
            tagsState = .loading
            do {
                tags = try await api.profileTags()
                tagsState = .loaded
            } catch {
                tagsState = .failed(Failure(error))
            }
        }
        tagsTask = task
        await task.value
        tagsTask = nil
    }

    public func gender(_ id: Int) -> Gender? { genders.first { $0.id == id } }

    public func pronoun(_ id: Int) -> Pronoun? { pronouns.first { $0.id == id } }

    // Genders and pronouns only name what profiles already carry, so a failure leaves them out quietly.
    private func loadGenders() async {
        guard genders.isEmpty, let genders = try? await api.genders() else { return }
        self.genders = genders
    }

    private func loadPronouns() async {
        guard pronouns.isEmpty, let pronouns = try? await api.pronouns() else { return }
        self.pronouns = pronouns
    }
}
