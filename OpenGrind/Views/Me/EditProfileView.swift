import OpenGrindKit
import SwiftUI

/// Edits your profile; only changed fields are sent.
struct EditProfileView: View {
    let me: MeModel
    private let original: ProfileEdit

    @Environment(\.dismiss) private var dismiss
    @State private var edit: ProfileEdit
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false
    @State private var failure: Failure?

    init(profile: Profile, me: MeModel) {
        self.me = me
        original = ProfileEdit(profile)
        _edit = State(initialValue: ProfileEdit(profile))
    }

    private var hasChanges: Bool { edit != original }

    var body: some View {
        NavigationStack {
            Form {
                aboutSection
                statsSection
                expectationsSection
                identitySection
                healthSection
                Section {
                    Toggle("Show Distance", isOn: $edit.showsDistance)
                } footer: {
                    Text("When off, others don't see how far away you are.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(!hasChanges || !edit.isValid)
                    }
                }
            }
            .disabled(isSaving)
            .interactiveDismissDisabled(hasChanges || isSaving)
            .confirmationDialog("Discard Changes?", isPresented: $isConfirmingDiscard) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .failureAlert($failure)
        }
    }

    // MARK: Sections

    private var aboutSection: some View {
        Section {
            TextField("Display Name", text: $edit.displayName)
                .textContentType(.nickname)
                .overlay(alignment: .trailing) {
                    CharacterCount(count: edit.displayName.count, limit: ProfileEdit.maxDisplayNameLength)
                }
            TextField("About Me", text: $edit.aboutMe, axis: .vertical)
                .lineLimit(3...10)
        } header: {
            Text("About")
        } footer: {
            HStack {
                Text("Grindr reviews names and text before others see them.")
                Spacer()
                CharacterCount(count: edit.aboutMe.count, limit: ProfileEdit.maxAboutMeLength)
            }
        }
    }

    private var statsSection: some View {
        Section("Stats") {
            Picker("Age", selection: $edit.age) {
                Text("Not Specified").tag(Int?.none)
                ForEach(ProfileEdit.ageRange, id: \.self) { age in
                    Text(age, format: .number).tag(Int?.some(age))
                }
            }
            Toggle("Show Age", isOn: $edit.showsAge)
            Picker("Height", selection: heightBinding) {
                Text("Not Specified").tag(Int?.none)
                ForEach(
                    Int(BrowseFilters.heightBounds.lowerBound)...Int(BrowseFilters.heightBounds.upperBound),
                    id: \.self
                ) {
                    centimeters in
                    Text(Formatting.height(Double(centimeters))).tag(Int?.some(centimeters))
                }
            }
            .pickerStyle(.navigationLink)
            Picker("Weight", selection: weightBinding) {
                Text("Not Specified").tag(Int?.none)
                ForEach(WeightOption.all, id: \.grams) { option in
                    Text(Formatting.weight(Double(option.grams))).tag(Int?.some(option.grams))
                }
            }
            .pickerStyle(.navigationLink)
            AttributePicker(title: "Body Type", selection: $edit.bodyType)
            AttributePicker(title: "Position", selection: $edit.position)
            Toggle("Show Position", isOn: $edit.showsPosition)
            AttributePicker(title: "Ethnicity", selection: $edit.ethnicity)
            AttributePicker(title: "Relationship", selection: $edit.relationshipStatus)
        }
    }

    private var expectationsSection: some View {
        Section("Expectations") {
            MultiSelectRow(title: "Looking For", selection: $edit.lookingFor)
            MultiSelectRow(title: "Meet At", selection: $edit.meetAt)
            AttributePicker(title: "NSFW Pics", selection: $edit.acceptsNSFWPics)
        }
    }

    private var identitySection: some View {
        Section {
            MultiSelectRow(title: "Tribes", selection: $edit.tribes)
            Toggle("Show Tribes", isOn: $edit.showsTribes)
        } header: {
            Text("Identity")
        } footer: {
            Text("Gender and pronouns can be changed in the Grindr app.")
        }
    }

    private var healthSection: some View {
        Section {
            AttributePicker(
                title: "HIV Status", selection: $edit.hivStatus, options: HIVStatus.settableCases)
            Toggle("Show Last Tested", isOn: hasTestDate)
            if let lastTested = edit.lastTested {
                DatePicker(
                    "Last Tested",
                    selection: Binding(get: { lastTested }, set: { edit.lastTested = $0 }),
                    in: ...Date.now, displayedComponents: .date)
            }
            MultiSelectRow(
                title: "Practices", selection: $edit.sexualHealth,
                options: SexualHealthPractice.settableCases)
            MultiSelectRow(title: "Vaccinated", selection: $edit.vaccines)
        } header: {
            Text("Sexual Health")
        } footer: {
            Text("Everything here is optional and visible on your profile.")
        }
    }

    // MARK: Bindings

    private var hasTestDate: Binding<Bool> {
        Binding {
            edit.lastTested != nil
        } set: { isOn in
            edit.lastTested = isOn ? Calendar.current.startOfDay(for: .now) : nil
        }
    }

    /// Height in whole centimeters, so the picker can match the stored value.
    private var heightBinding: Binding<Int?> {
        Binding {
            edit.height.map { Int($0.rounded()) }
        } set: { centimeters in
            edit.height = centimeters.map(Double.init)
        }
    }

    /// Weight as the nearest option in the user's units.
    private var weightBinding: Binding<Int?> {
        Binding {
            edit.weight.map { WeightOption.nearest(to: $0).grams }
        } set: { grams in
            edit.weight = grams.map(Double.init)
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await me.save(edit, from: original)
                dismiss()
            } catch {
                failure = Failure(error)
            }
        }
    }
}

/// The weights offered in the picker: whole kilograms or whole pounds.
private enum WeightOption {
    struct Option {
        var grams: Int
    }

    static var all: [Option] {
        let bounds = BrowseFilters.weightBounds
        if Locale.current.measurementSystem == .metric {
            let kilograms = Int((bounds.lowerBound / 1000).rounded(.up))...Int(bounds.upperBound / 1000)
            return kilograms.map { Option(grams: $0 * 1000) }
        }
        let gramsPerPound = 453.59237
        let pounds =
            Int((bounds.lowerBound / gramsPerPound).rounded(.up))...Int(bounds.upperBound / gramsPerPound)
        return pounds.map { Option(grams: Int((Double($0) * gramsPerPound).rounded())) }
    }

    static func nearest(to grams: Double) -> Option {
        all.min { abs(Double($0.grams) - grams) < abs(Double($1.grams) - grams) }
            ?? Option(grams: Int(grams))
    }
}

/// "12/15", red when over the limit.
private struct CharacterCount: View {
    let count: Int
    let limit: Int

    var body: some View {
        Text("\(count)/\(limit)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(count > limit ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
            .accessibilityLabel("\(count) of \(limit) characters")
    }
}
