import OpenGrindKit
import SwiftUI

/// A form row that opens a checklist of profile options.
struct MultiSelectRow<Attribute: ProfileAttribute>: View {
    let title: LocalizedStringKey
    @Binding var selection: Set<Attribute>
    var options: [Attribute] = Array(Attribute.allCases)
    /// What an empty selection means, e.g. "Any" in filters.
    var emptyLabel: LocalizedStringKey = "Not Specified"

    var body: some View {
        NavigationLink {
            MultiSelectList(title: title, selection: $selection, options: options)
        } label: {
            LabeledContent(title) {
                if selection.isEmpty {
                    Text(emptyLabel)
                } else {
                    Text(options.filter(selection.contains).localizedList)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A checklist of profile options.
struct MultiSelectList<Attribute: ProfileAttribute>: View {
    let title: LocalizedStringKey
    @Binding var selection: Set<Attribute>
    let options: [Attribute]

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        if selection.contains(option) {
                            selection.remove(option)
                        } else {
                            selection.insert(option)
                        }
                    } label: {
                        HStack {
                            Text(option.localizedName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(option) {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .accessibilityAddTraits(selection.contains(option) ? .isSelected : [])
                }
            }
            if !selection.isEmpty {
                Section {
                    Button("Clear Selection", role: .destructive) { selection.removeAll() }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A picker for one profile option, or none.
struct AttributePicker<Attribute: ProfileAttribute>: View {
    let title: LocalizedStringKey
    @Binding var selection: Attribute?
    var options: [Attribute] = Array(Attribute.allCases)

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Not Specified").tag(Attribute?.none)
            ForEach(options) { option in
                Text(option.localizedName).tag(Attribute?.some(option))
            }
        }
    }
}
