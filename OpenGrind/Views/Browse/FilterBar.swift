import OpenGrindKit
import SwiftUI

/// The grid's filters as a row of chips that scrolls sideways: on-off filters
/// switch with a tap, ranges and options open a wheel from the bottom of the
/// screen, and tags open their list. Every change reloads the grid.
struct FilterBar: View {
    let filters: BrowseFilters
    let apply: (BrowseFilters) -> Void

    @State private var wheel: FilterWheel?
    @State private var isShowingTags = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if !filters.isDefault {
                    FilterChip(isActive: false) {
                        apply(BrowseFilters())
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.bold)
                    }
                    .accessibilityLabel("Clear Filters")
                }
                toggle("Online", \.onlineOnly)
                range(.age, "Age", filters.ages, bounds: BrowseFilters.ageBounds) { String($0) }
                option(.position, "Position", filters.positions)
                tagsChip
                toggle("Favorites", \.favoritesOnly)
                toggle("Photos", \.photosOnly)
                toggle("Face Photos", \.facePhotosOnly)
                range(
                    .height, "Height", FilterWheelSheet.whole(filters.heights),
                    bounds: FilterWheelSheet.whole(BrowseFilters.heightBounds)
                ) { Formatting.height(Double($0)) }
                range(
                    .weight, "Weight", FilterWheelSheet.whole(filters.weights),
                    bounds: FilterWheelSheet.whole(BrowseFilters.weightBounds)
                ) { Formatting.weight(Double($0)) }
                option(.lookingFor, "Looking For", filters.lookingFor)
                option(.tribes, "Tribes", filters.tribes)
                option(.bodyType, "Body Type", filters.bodyTypes)
                option(.relationship, "Relationship", filters.relationshipStatuses)
                option(.meetAt, "Meet At", filters.meetAt)
                option(.nsfwPics, "NSFW Pics", filters.acceptsNSFWPics)
                toggle("Not Chatted Today", \.notChattedToday)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: filters)
        .sheet(item: $wheel) { wheel in
            FilterWheelSheet(wheel: wheel, filters: filters, apply: apply)
        }
        .sheet(isPresented: $isShowingTags) {
            TagFilterSheet(filters: filters, apply: apply)
        }
    }

    private func toggle(_ title: LocalizedStringKey, _ path: WritableKeyPath<BrowseFilters, Bool>) -> some View {
        let isOn = filters[keyPath: path]
        return FilterChip(isActive: isOn) {
            var changed = filters
            changed[keyPath: path].toggle()
            apply(changed)
        } label: {
            Text(title)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Shows the range once it's narrowed, e.g. "Age 25–40" or "Age 30+".
    private func range(
        _ wheel: FilterWheel, _ title: LocalizedStringKey, _ range: ClosedRange<Int>, bounds: ClosedRange<Int>,
        label: (Int) -> String
    ) -> some View {
        let lower = range.lowerBound > bounds.lowerBound ? label(range.lowerBound) : nil
        let upper = range.upperBound < bounds.upperBound ? label(range.upperBound) : nil
        let value: String? =
            switch (lower, upper) {
            case (let lower?, let upper?): "\(lower)–\(upper)"
            case (let lower?, nil): String(localized: "\(lower)+")
            case (nil, let upper?): String(localized: "Up to \(upper)")
            case (nil, nil): nil
            }
        return wheelChip(wheel, title, value: value)
    }

    private func option<Attribute: ProfileAttribute>(
        _ wheel: FilterWheel, _ title: LocalizedStringKey, _ selection: Set<Attribute>
    ) -> some View {
        wheelChip(
            wheel, title, value: selection.isEmpty ? nil : Attribute.allCases.filter(selection.contains).localizedList)
    }

    private func wheelChip(_ wheel: FilterWheel, _ title: LocalizedStringKey, value: String?) -> some View {
        FilterChip(isActive: value != nil, opensPicker: true) {
            self.wheel = wheel
        } label: {
            if let value {
                Text(value).lineLimit(1)
            } else {
                Text(title)
            }
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(value.map { Text($0) } ?? Text("Any"))
    }

    private var tagsChip: some View {
        FilterChip(isActive: !filters.tags.isEmpty, opensPicker: true) {
            isShowingTags = true
        } label: {
            if filters.tags.isEmpty {
                Text("Tags")
            } else {
                Text("Tags \(filters.tags.count)")
            }
        }
        .accessibilityLabel("Tags")
        .accessibilityValue(filters.tags.isEmpty ? Text("Any") : Text("\(filters.tags.count) selected"))
    }
}

/// A capsule in the filter row, filled while its filter is set.
private struct FilterChip<Label: View>: View {
    let isActive: Bool
    /// Opens a wheel or list rather than switching on and off.
    var opensPicker = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                label
                if opensPicker {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isActive ? Color.brandForeground : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(isActive ? Color.brand : Color(.tertiarySystemFill), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// The filters set with a wheel.
enum FilterWheel: String, Identifiable {
    case age, height, weight
    case position, lookingFor, tribes, bodyType, relationship, meetAt, nsfwPics

    var id: String { rawValue }
}

/// A wheel from the bottom of the screen: two side by side for a range, one
/// for an option. Applies when it closes.
private struct FilterWheelSheet: View {
    let wheel: FilterWheel
    let apply: (BrowseFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: BrowseFilters

    init(wheel: FilterWheel, filters: BrowseFilters, apply: @escaping (BrowseFilters) -> Void) {
        self.wheel = wheel
        self.apply = apply
        _draft = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Any") { reset() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.height(300)])
        .sensoryFeedback(.selection, trigger: draft)
        // However it closes, including a swipe down.
        .onDisappear { apply(draft) }
    }

    private var title: LocalizedStringKey {
        switch wheel {
        case .age: "Age"
        case .height: "Height"
        case .weight: "Weight"
        case .position: "Position"
        case .lookingFor: "Looking For"
        case .tribes: "Tribes"
        case .bodyType: "Body Type"
        case .relationship: "Relationship"
        case .meetAt: "Meet At"
        case .nsfwPics: "NSFW Pics"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch wheel {
        case .age:
            RangeWheels(range: $draft.ages, bounds: BrowseFilters.ageBounds, values: Array(BrowseFilters.ageBounds)) {
                Text($0, format: .number)
            }
        case .height:
            RangeWheels(
                range: Self.whole($draft.heights), bounds: Self.whole(BrowseFilters.heightBounds),
                values: MeasurementOptions.centimeters
            ) { Text(Formatting.height(Double($0))) }
        case .weight:
            RangeWheels(
                range: Self.whole($draft.weights), bounds: Self.whole(BrowseFilters.weightBounds),
                values: MeasurementOptions.grams
            ) { Text(Formatting.weight(Double($0))) }
        case .position: OptionWheel(selection: $draft.positions.single())
        case .lookingFor: OptionWheel(selection: $draft.lookingFor.single())
        case .tribes: OptionWheel(selection: $draft.tribes.single())
        case .bodyType: OptionWheel(selection: $draft.bodyTypes.single())
        case .relationship: OptionWheel(selection: $draft.relationshipStatuses.single())
        case .meetAt: OptionWheel(selection: $draft.meetAt.single())
        case .nsfwPics: OptionWheel(selection: $draft.acceptsNSFWPics.single())
        }
    }

    /// Back to "Any" for this filter only.
    private func reset() {
        let none = BrowseFilters()
        switch wheel {
        case .age: draft.ages = none.ages
        case .height: draft.heights = none.heights
        case .weight: draft.weights = none.weights
        case .position: draft.positions = []
        case .lookingFor: draft.lookingFor = []
        case .tribes: draft.tribes = []
        case .bodyType: draft.bodyTypes = []
        case .relationship: draft.relationshipStatuses = []
        case .meetAt: draft.meetAt = []
        case .nsfwPics: draft.acceptsNSFWPics = []
        }
    }

    /// Centimeters or grams as whole numbers, for the wheels. The bounds are whole
    /// numbers too, so "Any" maps back to them exactly.
    static func whole(_ range: Binding<ClosedRange<Double>>) -> Binding<ClosedRange<Int>> {
        Binding {
            whole(range.wrappedValue)
        } set: {
            range.wrappedValue = Double($0.lowerBound)...Double($0.upperBound)
        }
    }

    static func whole(_ range: ClosedRange<Double>) -> ClosedRange<Int> {
        Int(range.lowerBound.rounded())...Int(range.upperBound.rounded())
    }
}

/// "From" and "To" wheels side by side; the outer bounds read "Any".
private struct RangeWheels: View {
    @Binding var range: ClosedRange<Int>
    let bounds: ClosedRange<Int>
    let values: [Int]
    let label: (Int) -> Text

    var body: some View {
        HStack(spacing: 0) {
            wheel("From", selection: lower) {
                Text("Any").tag(bounds.lowerBound)
                ForEach(values.filter { $0 > bounds.lowerBound && $0 <= range.upperBound }, id: \.self) { value in
                    label(value).tag(value)
                }
            }
            Text(verbatim: "–")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            wheel("To", selection: upper) {
                ForEach(values.filter { $0 >= range.lowerBound && $0 < bounds.upperBound }, id: \.self) { value in
                    label(value).tag(value)
                }
                Text("Any").tag(bounds.upperBound)
            }
        }
    }

    private func wheel(
        _ title: LocalizedStringKey, selection: Binding<Int>, @ViewBuilder options: () -> some View
    ) -> some View {
        Picker(title, selection: selection, content: options)
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            // Side by side, each wheel only takes touches on its own half.
            .clipped()
            .contentShape(.rect)
            .accessibilityLabel(Text(title))
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

    /// The wheel value shown for `value`, so a stored value between steps still matches a row.
    private func nearest(_ value: Int, isLower: Bool) -> Int {
        if value <= bounds.lowerBound { return bounds.lowerBound }
        if value >= bounds.upperBound { return bounds.upperBound }
        let options = values.filter { isLower ? $0 > bounds.lowerBound : $0 < bounds.upperBound }
        return MeasurementOptions.nearest(to: Double(value), in: options)
    }
}

/// One wheel of profile options, with "Any" first.
private struct OptionWheel<Attribute: ProfileAttribute>: View {
    @Binding var selection: Attribute?

    var body: some View {
        Picker("Option", selection: $selection) {
            Text("Any").tag(Attribute?.none)
            ForEach(Array(Attribute.allCases)) { option in
                Text(option.localizedName).tag(Attribute?.some(option))
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
    }
}

/// The tag list as a sheet; applies when it closes.
private struct TagFilterSheet: View {
    let apply: (BrowseFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: BrowseFilters

    init(filters: BrowseFilters, apply: @escaping (BrowseFilters) -> Void) {
        self.apply = apply
        _draft = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            TagPickerList(selection: $draft.tags)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onDisappear { apply(draft) }
    }
}
