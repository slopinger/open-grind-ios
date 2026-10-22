import OpenGrindKit
import SwiftUI

/// A row of chips above the grid that scrolls sideways: the button for every
/// filter (``FilterSheet``, which also clears them), then the common ones, those
/// that are set first. On-off filters switch with a tap, age opens two wheels
/// from the bottom of the screen, and options and tags open a checklist. Every
/// change reloads the grid.
struct FilterBar: View {
    let filters: BrowseFilters
    let apply: (BrowseFilters) -> Void

    @State private var picker: FilterPicker?

    var body: some View {
        // Set ones first, each group in the usual order.
        let chips = CommonFilter.allCases.filter(isSet) + CommonFilter.allCases.filter { !isSet($0) }
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                allFiltersChip
                ForEach(chips, id: \.self) { chip($0) }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .animation(.default, value: chips)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: filters)
        .sheet(item: $picker) { picker in
            sheet(picker)
        }
    }

    private func isSet(_ filter: CommonFilter) -> Bool {
        switch filter {
        case .online: filters.onlineOnly
        case .tags: !filters.tags.isEmpty
        case .age: filters.ages != BrowseFilters.ageBounds
        case .position: !filters.positions.isEmpty
        case .lookingFor: !filters.lookingFor.isEmpty
        case .favorites: filters.favoritesOnly
        }
    }

    @ViewBuilder
    private func chip(_ filter: CommonFilter) -> some View {
        switch filter {
        case .online: toggle("Online", \.onlineOnly)
        case .tags: tagsChip
        case .age: ageChip
        case .position: option(.position, "Position", filters.positions)
        case .lookingFor: option(.lookingFor, "Looking For", filters.lookingFor)
        case .favorites: toggle("Favorites", \.favoritesOnly)
        }
    }

    @ViewBuilder
    private func sheet(_ picker: FilterPicker) -> some View {
        switch picker {
        case .all:
            FilterSheet(filters: filters, apply: apply)
        case .age:
            FilterPickerSheet(filters: filters, apply: apply) { $draft in
                RangeWheels(range: $draft.ages, bounds: BrowseFilters.ageBounds, values: Array(BrowseFilters.ageBounds))
                {
                    Text($0, format: .number)
                }
                .padding(.horizontal)
                .navigationTitle("Age")
                .navigationBarTitleDisplayMode(.inline)
            } reset: {
                $0.ages = BrowseFilters.ageBounds
            }
            .presentationDetents([.height(300)])
        case .position:
            FilterPickerSheet(filters: filters, apply: apply) { $draft in
                MultiSelectList(title: "Position", selection: $draft.positions, options: Array(SexualPosition.allCases))
            } reset: {
                $0.positions = []
            }
            .presentationDetents([.medium, .large])
        case .lookingFor:
            FilterPickerSheet(filters: filters, apply: apply) { $draft in
                MultiSelectList(title: "Looking For", selection: $draft.lookingFor, options: Array(LookingFor.allCases))
            } reset: {
                $0.lookingFor = []
            }
            .presentationDetents([.medium, .large])
        case .tags:
            FilterPickerSheet(filters: filters, apply: apply) { $draft in
                TagPickerList(selection: $draft.tags)
            } reset: {
                $0.tags = []
            }
        }
    }

    private var allFiltersChip: some View {
        let count = filters.activeCount
        return FilterChip(isActive: count > 0) {
            picker = .all
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .fontWeight(.semibold)
            if count > 0 {
                Text(count, format: .number)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("Filters")
        .accessibilityValue(count > 0 ? Text("\(count) active") : Text("None"))
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

    /// Shows the range once it's narrowed: "25–40", "30+" or "Up to 40".
    private var ageChip: some View {
        pickerChip(.age, "Age", value: RangeWheels.summary(of: filters.ages, in: BrowseFilters.ageBounds) { "\($0)" })
    }

    /// Shows the options chosen, e.g. "Top or Vers Top".
    private func option<Attribute: ProfileAttribute>(
        _ picker: FilterPicker, _ title: LocalizedStringKey, _ selection: Set<Attribute>
    ) -> some View {
        let chosen = Attribute.allCases.filter(selection.contains).map(\.localizedName)
        return pickerChip(picker, title, value: chosen.isEmpty ? nil : chosen.formatted(.list(type: .or)))
    }

    private var tagsChip: some View {
        let count = filters.tags.count
        let value = String(AttributedString(localized: "^[\(count) Tag](inflect: true)").characters)
        return pickerChip(.tags, "Tags", value: count == 0 ? nil : value)
    }

    private func pickerChip(_ picker: FilterPicker, _ title: LocalizedStringKey, value: String?) -> some View {
        FilterChip(isActive: value != nil, opensPicker: true) {
            self.picker = picker
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
}

/// The filters with a chip of their own, in their usual order.
private enum CommonFilter: CaseIterable {
    case online, tags, age, position, lookingFor, favorites
}

/// What a chip opens.
private enum FilterPicker: String, Identifiable {
    case all, age, position, lookingFor, tags

    var id: String { rawValue }
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

/// One filter in a sheet from the bottom of the screen, with Done. Applies
/// when it closes.
private struct FilterPickerSheet<Content: View>: View {
    let apply: (BrowseFilters) -> Void
    /// Clears this sheet's filter, for the Reset button.
    let reset: (inout BrowseFilters) -> Void
    let content: (Binding<BrowseFilters>) -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var draft: BrowseFilters

    init(
        filters: BrowseFilters, apply: @escaping (BrowseFilters) -> Void,
        @ViewBuilder content: @escaping (Binding<BrowseFilters>) -> Content,
        reset: @escaping (inout BrowseFilters) -> Void
    ) {
        self.apply = apply
        self.reset = reset
        self.content = content
        _draft = State(initialValue: filters)
    }

    private var cleared: BrowseFilters {
        var cleared = draft
        reset(&cleared)
        return cleared
    }

    var body: some View {
        NavigationStack {
            content($draft)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Reset") { withAnimation { draft = cleared } }
                            .disabled(cleared == draft)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .sensoryFeedback(.selection, trigger: draft)
        // However it closes, including a swipe down.
        .onDisappear { apply(draft) }
    }
}
