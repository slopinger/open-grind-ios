extension Sequence where Element: Identifiable {
    /// The elements in order, leaving out repeated ids and the ids in `excluded`,
    /// e.g. what a new page adds to the items already loaded.
    func uniqued(excluding excluded: [Element.ID] = []) -> [Element] {
        var seen = Set(excluded)
        return filter { seen.insert($0.id).inserted }
    }
}
