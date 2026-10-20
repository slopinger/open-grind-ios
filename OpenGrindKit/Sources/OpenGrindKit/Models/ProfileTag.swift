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
    public var categories: [ProfileTagCategory]

    public init(categories: [ProfileTagCategory]) {
        self.categories = categories
    }

    /// The text of the tag with `key`, if the catalog has it.
    public func text(forKey key: String) -> String? {
        for category in categories {
            if let tag = category.tags.first(where: { $0.key == key }) { return tag.text }
        }
        return nil
    }

    /// Tags whose text contains `query`, each once, in catalog order.
    public func tags(matching query: String) -> [ProfileTag] {
        let query = query.trimmingCharacters(in: .whitespaces)
        var seen = Set<String>()
        return categories.flatMap(\.tags).filter { tag in
            (query.isEmpty || tag.text.localizedStandardContains(query)) && seen.insert(tag.key).inserted
        }
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
        categories = (languages.first?.categoryCollection.elements ?? []).compactMap { category in
            let tags = category.tags.elements.filter { !$0.key.isEmpty && !$0.text.isEmpty }
            guard !tags.isEmpty else { return nil }
            return ProfileTagCategory(
                name: category.text, tags: tags.map { ProfileTag(key: $0.key, text: $0.text) })
        }
    }
}
