import OpenGrindKit
import SwiftUI

/// Reports a profile to Grindr's moderators, and optionally blocks it.
struct ReportSheet: View {
    let name: String
    let send: (ProfileReport, _ alsoBlock: Bool) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var locations: Set<ReportLocation> = [.profileInformation]
    @State private var comment = ""
    @State private var alsoBlock = true
    @State private var isSending = false
    @State private var failure: Failure?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.localizedName).tag(Optional(reason))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Where") {
                    ForEach(ReportLocation.allCases) { location in
                        Toggle(location.localizedName, isOn: binding(for: location))
                    }
                }
                Section {
                    TextField("Details (optional)", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("Grindr's moderators review reports. \(name) isn't told who reported them.")
                }
                Section {
                    Toggle("Also Block \(name)", isOn: $alsoBlock)
                }
            }
            .navigationTitle("Report \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send", action: submit)
                            .disabled(reason == nil || locations.isEmpty)
                    }
                }
            }
            .disabled(isSending)
            .interactiveDismissDisabled(isSending)
            .failureAlert($failure)
        }
    }

    private func binding(for location: ReportLocation) -> Binding<Bool> {
        Binding {
            locations.contains(location)
        } set: { isOn in
            if isOn { locations.insert(location) } else { locations.remove(location) }
        }
    }

    private func submit() {
        guard let reason else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await send(
                    ProfileReport(
                        reason: reason, locations: locations,
                        comment: comment.trimmingCharacters(in: .whitespacesAndNewlines)),
                    alsoBlock)
                dismiss()
            } catch {
                failure = Failure(error)
            }
        }
    }
}
