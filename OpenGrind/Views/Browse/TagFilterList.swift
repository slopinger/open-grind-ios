import OpenGrindKit
import SwiftUI

/// A form row that opens the tag checklist; shows the chosen tags.
struct TagFilterRow: View {
    @Binding var selection: Set<String>

    @Environment(AccountSession.self) private var session

    var body: some View {
        NavigationLink {
            TagFilterList(selection: $selection)
        } label: {
            LabeledContent("Tags") {
                if selection.isEmpty {
                    Text("Any")
                } else if let catalog = session.browse.tagCatalog {
                    Text(selection.sorted().map { catalog.text(forKey: $0) ?? $0 }.formatted(.list(type: .or)))
                        .lineLimit(1)
                } else {
                    Text("\(selection.count) selected")
                }
            }
        }
        .task { await session.browse.loadTagCatalog() }
    }
}

/// Every tag Grindr offers, by category, searchable. Profiles with any chosen
/// tag match.
struct TagFilterList: View {
    @Binding var selection: Set<String>

    @Environment(AccountSession.self) private var session
    @State private var query = ""

    private var browse: BrowseModel { session.browse }

    var body: some View {
        Group {
            if let catalog = browse.tagCatalog {
                list(catalog)
            } else if let failure = browse.tagCatalogState.failure {
                FailureView(failure: failure) { await browse.loadTagCatalog() }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Tags")
        .sensoryFeedback(.selection, trigger: selection)
        .task { await browse.loadTagCatalog() }
    }

    @ViewBuilder
    private func list(_ catalog: ProfileTagCatalog) -> some View {
        List {
            if !selection.isEmpty, query.isEmpty {
                Section {
                    Button("Clear Selection", role: .destructive) { selection.removeAll() }
                } footer: {
                    Text("Shows profiles with any of the selected tags.")
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
        return Button {
            if isSelected {
                selection.remove(tag.key)
            } else {
                selection.insert(tag.key)
            }
        } label: {
            HStack {
                Text(tag.text)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
