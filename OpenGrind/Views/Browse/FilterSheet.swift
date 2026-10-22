import OpenGrindKit
import SwiftUI

/// Narrows down the nearby grid. Changes apply when the sheet closes.
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
                    Toggle("Online Now", isOn: $filters.onlineOnly)
                    Toggle("With Photos", isOn: $filters.photosOnly)
                    Toggle("With Face Photos", isOn: $filters.facePhotosOnly)
                    Toggle("Favorites", isOn: $filters.favoritesOnly)
                    Toggle("Not Chatted Today", isOn: $filters.notChattedToday)
                }

                Section("Age") {
                    RangePicker(
                        id: "age", range: $filters.ages, bounds: BrowseFilters.ageBounds,
                        values: Array(BrowseFilters.ageBounds), openWheel: $openWheel
                    ) { Text($0, format: .number) }
                }

                Section("Height") {
                    RangePicker(
                        id: "height", range: whole($filters.heights), bounds: whole(BrowseFilters.heightBounds),
                        values: MeasurementOptions.centimeters, openWheel: $openWheel
                    ) { Text(Formatting.height(Double($0))) }
                }

                Section("Weight") {
                    RangePicker(
                        id: "weight", range: whole($filters.weights), bounds: whole(BrowseFilters.weightBounds),
                        values: MeasurementOptions.grams, openWheel: $openWheel
                    ) { Text(Formatting.weight(Double($0))) }
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

                Section {
                    TagPickerRow(selection: $filters.tags, emptyLabel: "Any")
                } footer: {
                    Text("Tags are interests people add to their profile.")
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

/// "From" and "To" rows for a range, each with a wheel; the outer bounds read "Any".
private struct RangePicker: View {
    let id: String
    @Binding var range: ClosedRange<Int>
    let bounds: ClosedRange<Int>
    let values: [Int]
    @Binding var openWheel: String?
    let label: (Int) -> Text

    var body: some View {
        WheelPickerRow(
            "From", value: text(lower.wrappedValue), selection: lower, isExpanded: $openWheel.isOpen("\(id).from")
        ) {
            Text("Any").tag(bounds.lowerBound)
            ForEach(values.filter { $0 > bounds.lowerBound && $0 <= range.upperBound }, id: \.self) { value in
                label(value).tag(value)
            }
        }
        WheelPickerRow(
            "To", value: text(upper.wrappedValue), selection: upper, isExpanded: $openWheel.isOpen("\(id).to")
        ) {
            ForEach(values.filter { $0 >= range.lowerBound && $0 < bounds.upperBound }, id: \.self) { value in
                label(value).tag(value)
            }
            Text("Any").tag(bounds.upperBound)
        }
    }

    private func text(_ value: Int) -> Text {
        value == bounds.lowerBound || value == bounds.upperBound ? Text("Any") : label(value)
    }

    private var lower: Binding<Int> {
        Binding {
            nearest(range.lowerBound, isLower: true)
        } set: {
            range = $0...max($0, range.upperBound)
        }
    }

    private var upper: Binding<Int> {
        Binding {
            nearest(range.upperBound, isLower: false)
        } set: {
            range = min(range.lowerBound, $0)...$0
        }
    }

    /// The picker value shown for `value`, so a stored value between steps still matches a row.
    private func nearest(_ value: Int, isLower: Bool) -> Int {
        if value <= bounds.lowerBound { return bounds.lowerBound }
        if value >= bounds.upperBound { return bounds.upperBound }
        let options = values.filter { isLower ? $0 > bounds.lowerBound : $0 < bounds.upperBound }
        return MeasurementOptions.nearest(to: Double(value), in: options)
    }
}
