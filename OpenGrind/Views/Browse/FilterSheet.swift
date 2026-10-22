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
                    MultiSelectRow(title: "Position", selection: $filters.positions, emptyLabel: "Any")
                    MultiSelectRow(title: "Looking For", selection: $filters.lookingFor, emptyLabel: "Any")
                    MultiSelectRow(title: "Tribes", selection: $filters.tribes, emptyLabel: "Any")
                    MultiSelectRow(title: "Body Type", selection: $filters.bodyTypes, emptyLabel: "Any")
                    MultiSelectRow(
                        title: "Relationship", selection: $filters.relationshipStatuses, emptyLabel: "Any")
                    MultiSelectRow(title: "Meet At", selection: $filters.meetAt, emptyLabel: "Any")
                    MultiSelectRow(title: "NSFW Pics", selection: $filters.acceptsNSFWPics, emptyLabel: "Any")
                }

                if !filters.isDefault {
                    Section {
                        Button("Reset Filters", role: .destructive) {
                            withAnimation { filters = BrowseFilters() }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
