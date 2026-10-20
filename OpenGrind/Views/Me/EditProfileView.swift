import OpenGrindKit
import SwiftUI

/// Edits your profile; only changed fields are sent. Photos are saved as you
/// change them, on their own screen.
struct EditProfileView: View {
    let me: MeModel
    private let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSession.self) private var session
    /// What the form started with; its tags are matched to the catalog once it loads.
    @State private var original: ProfileEdit
    @State private var edit: ProfileEdit
    @State private var openWheel: String?
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false
    @State private var failure: Failure?

    init(profile: Profile, me: MeModel, tagCatalog: ProfileTagCatalog?) {
        self.me = me
        self.profile = profile
        let edit = ProfileEdit(profile, tagCatalog: tagCatalog)
        _original = State(initialValue: edit)
        _edit = State(initialValue: edit)
    }

    private var hasChanges: Bool { edit != original }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                aboutSection
                tagsSection
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
            .task { await session.browse.loadTagCatalog() }
            .onChange(of: session.browse.tagCatalog) { _, catalog in
                // Opened before the catalog arrived: match the tags now, unless they were edited.
                guard let catalog, edit.tags == original.tags else { return }
                let tags = ProfileEdit(profile, tagCatalog: catalog).tags
                original.tags = tags
                edit.tags = tags
            }
        }
    }

    // MARK: Sections

    private var photosSection: some View {
        let photos = me.profile?.photos ?? []
        return Section {
            NavigationLink {
                EditPhotosView()
            } label: {
                LabeledContent {
                    HStack(spacing: -8) {
                        ForEach(photos.prefix(MeModel.maxPhotos)) { photo in
                            Avatar(photoHash: photo.mediaHash, size: 32)
                                .overlay {
                                    Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2)
                                }
                        }
                    }
                } label: {
                    Text("Photos")
                }
            }
            .accessibilityValue(Text("\(photos.count) of \(MeModel.maxPhotos)"))
        } footer: {
            Text("Photo changes are saved right away.")
        }
    }

    private var tagsSection: some View {
        Section {
            TagPickerRow(selection: tagKeys, limit: ProfileEdit.maxTags)
        } footer: {
            Text("Up to \(ProfileEdit.maxTags) interests that show on your profile and help people find you.")
        }
    }

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
            WheelPickerRow(
                "Age", value: edit.age.map { Text($0, format: .number) } ?? Text("Not Specified"),
                selection: $edit.age, isExpanded: $openWheel.isOpen("age")
            ) {
                Text("Not Specified").tag(Int?.none)
                ForEach(ProfileEdit.ageRange, id: \.self) { age in
                    Text(age, format: .number).tag(Int?.some(age))
                }
            }
            Toggle("Show Age", isOn: $edit.showsAge)
            WheelPickerRow(
                "Height", value: edit.height.map { Text(Formatting.height($0)) } ?? Text("Not Specified"),
                selection: heightBinding, isExpanded: $openWheel.isOpen("height")
            ) {
                Text("Not Specified").tag(Int?.none)
                ForEach(
                    Int(BrowseFilters.heightBounds.lowerBound)...Int(BrowseFilters.heightBounds.upperBound),
                    id: \.self
                ) {
                    centimeters in
                    Text(Formatting.height(Double(centimeters))).tag(Int?.some(centimeters))
                }
            }
            WheelPickerRow(
                "Weight", value: edit.weight.map { Text(Formatting.weight($0)) } ?? Text("Not Specified"),
                selection: weightBinding, isExpanded: $openWheel.isOpen("weight")
            ) {
                Text("Not Specified").tag(Int?.none)
                ForEach(WeightOption.all, id: \.grams) { option in
                    Text(Formatting.weight(Double(option.grams))).tag(Int?.some(option.grams))
                }
            }
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
        Section("Identity") {
            ChoiceRow(
                title: "Gender", selection: $edit.genderIDs, choices: genderChoices, limit: ProfileEdit.maxGenders)
            ChoiceRow(
                title: "Pronouns", selection: $edit.pronounIDs,
                choices: me.pronouns.map { Choice(id: $0.id, name: $0.name) }, limit: ProfileEdit.maxPronouns)
            MultiSelectRow(title: "Tribes", selection: $edit.tribes)
            Toggle("Show Tribes", isOn: $edit.showsTribes)
        }
    }

    /// The genders a profile can show, plus any you have that are no longer offered.
    private var genderChoices: [Choice] {
        let offered = Gender.profileOptions(me.genders)
        let kept = edit.genderIDs.filter { id in !offered.contains { $0.id == id } }.compactMap { me.gender($0) }
        return (offered + kept).map { Choice(id: $0.id, name: $0.name, excludes: $0.excludedOnProfile) }
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

    /// The chosen tags by key, for the tag list.
    private var tagKeys: Binding<Set<String>> {
        Binding {
            Set(edit.tags.map(\.key))
        } set: { keys in
            let catalog = session.browse.tagCatalog
            let current = edit.tags
            edit.tags = Set(
                keys.map { key in
                    current.first { $0.key == key } ?? catalog?.tag(forKey: key) ?? ProfileTag(key: key, text: key)
                })
        }
    }

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
