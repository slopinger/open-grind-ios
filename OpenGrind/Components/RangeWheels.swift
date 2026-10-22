import SwiftUI

/// "From" and "To" wheels side by side for a range; the outer bounds read "Any".
struct RangeWheels: View {
    @Binding var range: ClosedRange<Int>
    let bounds: ClosedRange<Int>
    /// Every value a wheel offers, including the bounds.
    let values: [Int]
    let label: (Int) -> Text

    var body: some View {
        HStack(spacing: 0) {
            wheel("From", selection: lower) {
                Text("Any").tag(bounds.lowerBound)
                ForEach(values.filter { $0 > bounds.lowerBound && $0 <= upper.wrappedValue }, id: \.self) { value in
                    label(value).tag(value)
                }
            }
            Text(verbatim: "–")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            wheel("To", selection: upper) {
                ForEach(values.filter { $0 >= lower.wrappedValue && $0 < bounds.upperBound }, id: \.self) { value in
                    label(value).tag(value)
                }
                Text("Any").tag(bounds.upperBound)
            }
        }
    }

    /// The range in words, or `nil` when it's all of `bounds`: "25–40", "30+" or "Up to 40".
    static func summary(of range: ClosedRange<Int>, in bounds: ClosedRange<Int>, label: (Int) -> String) -> String? {
        let lower = range.lowerBound > bounds.lowerBound ? label(range.lowerBound) : nil
        let upper = range.upperBound < bounds.upperBound ? label(range.upperBound) : nil
        return switch (lower, upper) {
        case (let lower?, let upper?): "\(lower)–\(upper)"
        case (let lower?, nil): String(localized: "\(lower)+")
        case (nil, let upper?): String(localized: "Up to \(upper)")
        case (nil, nil): nil
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

/// A form row for a range: shows it, and tapping it opens ``RangeWheels``
/// below, like ``WheelPickerRow`` does for one number.
struct RangeWheelRow: View {
    let title: LocalizedStringKey
    @Binding var range: ClosedRange<Int>
    let bounds: ClosedRange<Int>
    let values: [Int]
    @Binding var isExpanded: Bool
    let label: (Int) -> String

    var body: some View {
        let value = Text(RangeWheels.summary(of: range, in: bounds, label: label) ?? String(localized: "Any"))
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            LabeledContent {
                value
                    .monospacedDigit()
                    .foregroundStyle(isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
            } label: {
                // Color.primary rather than .primary: inside a button, .primary is the tint.
                Text(title)
                    .foregroundStyle(Color.primary)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(value)
        .accessibilityHint(isExpanded ? Text("Hides the picker.") : Text("Shows a picker."))

        if isExpanded {
            RangeWheels(range: $range, bounds: bounds, values: values) { Text(label($0)) }
        }
    }
}
