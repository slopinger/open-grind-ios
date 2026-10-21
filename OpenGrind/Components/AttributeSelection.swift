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
                    CheckRow(title: option.localizedName, isSelected: selection.contains(option)) {
                        selection.toggle(option)
                    }
                }
            }
            if !selection.isEmpty {
                Section {
                    ClearSelectionButton { selection.removeAll() }
                }
            }
        }
        .checklistPage(title, selection: selection)
    }
}

/// A checklist row: the option, with a checkmark while it is chosen.
struct CheckRow: View {
    let title: String
    let isSelected: Bool
    /// Off when the option can't be added, e.g. past a limit.
    var isEnabled = true
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Empties a checklist.
struct ClearSelectionButton: View {
    let clear: () -> Void

    var body: some View {
        Button("Clear Selection", role: .destructive, action: clear)
    }
}

extension View {
    /// The title and selection haptics every checklist page shares.
    func checklistPage(_ title: LocalizedStringKey, selection: some Equatable) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A picker for one profile option, or none. Opens a list like the multiple
/// choice rows, so every option row in a form behaves the same.
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
        .pickerStyle(.navigationLink)
    }
}
