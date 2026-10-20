import OpenGrindKit
import SwiftUI

/// A form row that opens the tag checklist; shows the chosen tags by key.
struct TagPickerRow: View {
    @Binding var selection: Set<String>
    /// What an empty selection means, e.g. "Any" in filters.
    var emptyLabel: LocalizedStringKey = "None"
    /// How many tags can be chosen, if limited.
    var limit: Int?

    @Environment(AccountSession.self) private var session

    var body: some View {
        NavigationLink {
            TagPickerList(selection: $selection, limit: limit)
        } label: {
            LabeledContent("Tags") {
                if selection.isEmpty {
                    Text(emptyLabel)
                } else if let catalog = session.catalogs.tags {
                    Text(
                        selection.map { catalog.tag(forKey: $0)?.text ?? $0 }.sorted()
                            .formatted(.list(type: limit == nil ? .or : .and))
                    )
                    .lineLimit(1)
                } else {
                    Text("\(selection.count) selected")
                }
            }
        }
        .task { await session.catalogs.loadTags() }
    }
}

/// Every tag Grindr offers, by category, searchable. Without a limit it's a
/// filter: profiles with any chosen tag match.
struct TagPickerList: View {
    @Binding var selection: Set<String>
    var limit: Int?

    @Environment(AccountSession.self) private var session
    @State private var query = ""

    private var catalogs: CatalogModel { session.catalogs }

    var body: some View {
        Group {
            if let catalog = catalogs.tags {
                list(catalog)
            } else if let failure = catalogs.tagsState.failure {
                FailureView(failure: failure) { await catalogs.loadTags() }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Tags")
        .sensoryFeedback(.selection, trigger: selection)
        .task { await catalogs.loadTags() }
    }

    @ViewBuilder
    private func list(_ catalog: ProfileTagCatalog) -> some View {
        List {
            if query.isEmpty, !selection.isEmpty || limit != nil {
                Section {
                    if !selection.isEmpty {
                        Button("Clear Selection", role: .destructive) { selection.removeAll() }
                    }
                } footer: {
                    if let limit {
                        Text("\(selection.count) of \(limit) chosen. Your tags appear on your profile.")
                    } else {
                        Text("Shows profiles with any of the selected tags.")
                    }
                }
            }
            if query.isEmpty {
                ForEach(catalog.categories) { category in
                    Section(category.name) {
                        ForEach(category.tags) { row($0) }
                    }
                }
            } else {
                let matches = catalog.tags(matching: query)
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(matches) { row($0) }
                }
            }
        }
    }

    private func row(_ tag: ProfileTag) -> some View {
        let isSelected = selection.contains(tag.key)
        let isFull = limit.map { selection.count >= $0 } ?? false
        return Button {
            if isSelected {
                selection.remove(tag.key)
            } else {
                selection.insert(tag.key)
            }
        } label: {
            HStack {
                Text(tag.text)
                    .foregroundStyle(isFull && !isSelected ? Color.secondary : Color.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .disabled(isFull && !isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
