import SwiftUI

/// An option that Grindr identifies by number, such as a gender.
struct Choice: Identifiable, Hashable {
    var id: Int
    var name: String
    /// Options that can't be chosen together with this one.
    var excludes: [Int] = []
}

/// A form row that opens a checklist of up to `limit` choices, kept in the
/// order they were chosen.
struct ChoiceRow: View {
    let title: LocalizedStringKey
    @Binding var selection: [Int]
    let choices: [Choice]
    let limit: Int
    var emptyLabel: LocalizedStringKey = "Not Specified"

    var body: some View {
        NavigationLink {
            ChoiceList(title: title, selection: $selection, choices: choices, limit: limit)
        } label: {
            LabeledContent(title) {
                let names = selection.compactMap { id in choices.first { $0.id == id }?.name }
                if names.isEmpty {
                    Text(emptyLabel)
                } else {
                    Text(names.formatted(.list(type: .and)))
                        .lineLimit(1)
                }
            }
        }
        // The options come with your profile; without them there is nothing to choose.
        .disabled(choices.isEmpty)
    }
}

/// A checklist of choices with a limit and options that exclude each other.
struct ChoiceList: View {
    let title: LocalizedStringKey
    @Binding var selection: [Int]
    let choices: [Choice]
    let limit: Int

    var body: some View {
        List {
            Section {
                ForEach(choices) { choice in
                    row(choice)
                }
            } footer: {
                Text("Choose up to \(limit).")
            }
            if !selection.isEmpty {
                Section {
                    ClearSelectionButton { selection.removeAll() }
                }
            }
        }
        .checklistPage(title, selection: selection)
    }

    private func row(_ choice: Choice) -> some View {
        let isSelected = selection.contains(choice.id)
        let isAvailable = isSelected || (selection.count < limit && !isExcluded(choice))
        return CheckRow(title: choice.name, isSelected: isSelected, isEnabled: isAvailable) {
            if isSelected {
                selection.removeAll { $0 == choice.id }
            } else {
                selection.append(choice.id)
            }
        }
    }

    /// Whether a chosen option rules this one out, or this one rules out a chosen option.
    private func isExcluded(_ choice: Choice) -> Bool {
        selection.contains { id in
            choice.excludes.contains(id) || choices.first { $0.id == id }?.excludes.contains(choice.id) == true
        }
    }
}
