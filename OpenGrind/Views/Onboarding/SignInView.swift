import OpenGrindKit
import SwiftUI

/// Email and password sign-in, with Password AutoFill.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var failure: Failure?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && !isSigningIn
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                } footer: {
                    Text(
                        "Use the email and password of your Grindr account. They are sent only to Grindr; Open Grind keeps a session token in your Keychain, never your password."
                    )
                }

                if let failure {
                    Section {
                        Label {
                            let text = Self.describe(failure)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(text.title).font(.headline)
                                Text(text.message).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                } footer: {
                    Text(
                        "Forgot your password? Reset it in the Grindr app or on grindr.com. Only email sign-in is supported: accounts that use Apple, Google, Facebook or a phone number can't sign in yet."
                    )
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Button("Sign In", action: signIn)
                            .disabled(!canSubmit)
                    }
                }
            }
            .disabled(isSigningIn)
            .interactiveDismissDisabled(isSigningIn)
            .onAppear { focusedField = .email }
            .sensoryFeedback(.error, trigger: failure) { _, new in new != nil }
        }
    }

    private func signIn() {
        guard canSubmit else { return }
        failure = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await model.account.signIn(email: email, password: password)
                dismiss()
            } catch {
                failure = Failure(error)
                focusedField = .password
            }
        }
    }

    /// The usual wording, except that a refused sign-in is about what was typed.
    private static func describe(_ failure: Failure) -> (title: String, message: String) {
        if case .grindr(.unauthorized) = failure {
            return (
                String(localized: "Wrong Email or Password"), String(localized: "Check your details and try again.")
            )
        }
        let text = FailureText(failure)
        return (text.title, text.message)
    }
}
