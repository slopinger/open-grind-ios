import OpenGrindKit
import SwiftUI

/// Every filter for the nearby grid. Changes apply when the sheet closes.
struct FilterSheet: View {
    let apply: (BrowseFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filters: BrowseFilters
    @State private var openWheel: String?

    init(filters: BrowseFilters, apply: @escaping (BrowseFilters) -> Void) {
        self.apply = apply
        _filters = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TagPickerRow(selection: $filters.tags, emptyLabel: "Any")
                } footer: {
                    Text("Tags are interests people add to their profile.")
                }

                Section {
                    Toggle("Online Now", isOn: $filters.onlineOnly)
                    Toggle("With Photos", isOn: $filters.photosOnly)
                    Toggle("With Face Photos", isOn: $filters.facePhotosOnly)
                    Toggle("With Albums", isOn: $filters.albumsOnly)
                    Toggle("Favorites", isOn: $filters.favoritesOnly)
                    Toggle("Not Chatted Today", isOn: $filters.notChattedToday)
                }

                Section {
                    RangeWheelRow(
                        title: "Age", range: $filters.ages, bounds: BrowseFilters.ageBounds,
                        values: Array(BrowseFilters.ageBounds), isExpanded: $openWheel.isOpen("age")
                    ) { "\($0)" }
                    RangeWheelRow(
                        title: "Height", range: whole($filters.heights), bounds: whole(BrowseFilters.heightBounds),
                        values: MeasurementOptions.centimeters, isExpanded: $openWheel.isOpen("height")
                    ) { Formatting.height(Double($0)) }
                    RangeWheelRow(
                        title: "Weight", range: whole($filters.weights), bounds: whole(BrowseFilters.weightBounds),
                        values: MeasurementOptions.grams, isExpanded: $openWheel.isOpen("weight")
                    ) { Formatting.weight(Double($0)) }
                }

                Section("Details") {
                    GenderFilterRow(selection: $filters.genders)
                    MultiSelectRow(title: "Position", selection: $filters.positions, emptyLabel: "Any")
                    MultiSelectRow(title: "Looking For", selection: $filters.lookingFor, emptyLabel: "Any")
                    MultiSelectRow(title: "Tribes", selection: $filters.tribes, emptyLabel: "Any")
                    MultiSelectRow(title: "Body Type", selection: $filters.bodyTypes, emptyLabel: "Any")
                    MultiSelectRow(
                        title: "Relationship", selection: $filters.relationshipStatuses, emptyLabel: "Any")
                    MultiSelectRow(title: "Meet At", selection: $filters.meetAt, emptyLabel: "Any")
                    MultiSelectRow(title: "NSFW Pics", selection: $filters.acceptsNSFWPics, emptyLabel: "Any")
                    MultiSelectRow(
                        title: "Sexual Health", selection: $filters.sexualHealth,
                        options: SexualHealthPractice.settableCases, emptyLabel: "Any")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Up here rather than below the form, so it's always in reach.
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        withAnimation {
                            filters = BrowseFilters()
                            openWheel = nil
                        }
                    }
                    .disabled(filters.isDefault)
                    .accessibilityLabel("Reset Filters")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // On the stack, not the form, so opening the tag list doesn't count as leaving.
        // Applies however the sheet closes, including a swipe down.
        .onDisappear { apply(filters) }
    }

    /// Centimeters or grams as whole numbers, for the wheels. The bounds are whole
    /// numbers too, so "Any" maps back to them exactly.
    private func whole(_ range: Binding<ClosedRange<Double>>) -> Binding<ClosedRange<Int>> {
        Binding {
            whole(range.wrappedValue)
        } set: {
            range.wrappedValue = Double($0.lowerBound)...Double($0.upperBound)
        }
    }

    private func whole(_ range: ClosedRange<Double>) -> ClosedRange<Int> {
        Int(range.lowerBound.rounded())...Int(range.upperBound.rounded())
    }
}

/// Opens a checklist of the genders to filter by, from Grindr's catalog.
private struct GenderFilterRow: View {
    @Binding var selection: Set<Int>

    @Environment(AccountSession.self) private var session

    var body: some View {
        let options = Gender.filterOptions(session.catalogs.genders)
        NavigationLink {
            List {
                Section {
                    ForEach(options) { gender in
                        CheckRow(title: gender.name, isSelected: selection.contains(gender.id)) {
                            selection.toggle(gender.id)
                        }
                    }
                }
                if !selection.isEmpty {
                    Section {
                        ClearSelectionButton { selection.removeAll() }
                    }
                }
            }
            .checklistPage("Gender", selection: selection)
        } label: {
            LabeledContent("Gender") {
                let names = options.filter { selection.contains($0.id) }.map(\.name)
                if names.isEmpty {
                    Text("Any")
                } else {
                    Text(names.formatted(.list(type: .or)))
                        .lineLimit(1)
                }
            }
        }
        // The catalog comes with your profile; without it there is nothing to choose.
        .disabled(options.isEmpty)
        .task { await session.catalogs.loadIfNeeded() }
    }
}
