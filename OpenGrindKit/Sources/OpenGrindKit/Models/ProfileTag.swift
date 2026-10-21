import Foundation

/// A tag people can put on their profile, such as "Hiking". Profiles show the
/// tag's text; the nearby grid filters by its key.
public struct ProfileTag: Identifiable, Hashable, Sendable {
    /// Stable, language-independent, e.g. `hiking`.
    public var key: String
    /// In the language Grindr answered in, e.g. "Hiking" or "Wandern".
    public var text: String

    public var id: String { key }

    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

/// A group of tags, such as "Hobbies".
public struct ProfileTagCategory: Identifiable, Hashable, Sendable {
    public var name: String
    public var tags: [ProfileTag]

    public var id: String { name }

    public init(name: String, tags: [ProfileTag]) {
        self.name = name
        self.tags = tags
    }
}

/// Every tag Grindr offers (`GET /v1/tags`), grouped by category.
public struct ProfileTagCatalog: Hashable, Sendable {
    public let categories: [ProfileTagCategory]
    /// Every tag once, in catalog order.
    public let tags: [ProfileTag]
    private let tagsByKey: [String: ProfileTag]
    private let keysByText: [String: String]

    public init(categories: [ProfileTagCategory]) {
        self.categories = categories
        tags = categories.flatMap(\.tags).uniqued()
        tagsByKey = Dictionary(tags.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        keysByText = Dictionary(tags.map { ($0.text, $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    public func tag(forKey key: String) -> ProfileTag? { tagsByKey[key] }

    /// The key for a tag as a profile carries it: profiles carry either the key or
    /// the text. Values the catalog doesn't know stay as they are.
    public func key(for value: String) -> String {
        tagsByKey[value] != nil ? value : keysByText[value] ?? value
    }

    /// The text to show for a tag's key or text. Values the catalog doesn't know
    /// are shown as they are.
    public func text(for value: String) -> String {
        tagsByKey[value]?.text ?? value
    }

    /// Tags whose text contains `query`, in catalog order.
    public func tags(matching query: String) -> [ProfileTag] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? tags : tags.filter { $0.text.localizedStandardContains(query) }
    }
}

extension ProfileTagCatalog: Decodable {
    /// The response lists the catalog once per language; the first is the one
    /// matching the request's locale.
    private struct Language: Decodable {
        var categoryCollection: LossyArray<Category>
    }

    private struct Category: Decodable {
        var text: String
        var tags: LossyArray<Tag>
    }

    private struct Tag: Decodable {
        var key: String
        var text: String
    }

    public init(from decoder: any Decoder) throws {
        let languages = try LossyArray<Language>(from: decoder).elements
        let categories: [ProfileTagCategory] = (languages.first?.categoryCollection.elements ?? []).compactMap {
            category in
            let tags = category.tags.elements.filter { !$0.key.isEmpty && !$0.text.isEmpty }
            guard !tags.isEmpty else { return nil }
            return ProfileTagCategory(
                name: category.text, tags: tags.map { ProfileTag(key: $0.key, text: $0.text) })
        }
        self.init(categories: categories)
    }
}
