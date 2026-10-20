import SwiftUI

/// A form row for a number: shows the value, and tapping it opens a wheel below
/// it, like the date rows in Calendar or the measurements in Health.
struct WheelPickerRow<Value: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    let value: Text
    @Binding var selection: Value
    @Binding var isExpanded: Bool
    let options: Options

    init(
        _ title: LocalizedStringKey, value: Text, selection: Binding<Value>, isExpanded: Binding<Bool>,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.value = value
        _selection = selection
        _isExpanded = isExpanded
        self.options = options()
    }

    var body: some View {
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
            Picker(title, selection: $selection) {
                options
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
    }
}
