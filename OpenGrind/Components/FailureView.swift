import OpenGrindKit
import SwiftUI

/// A full-screen explanation of why content could not load, with a way out.
struct FailureView: View {
    let failure: Failure
    let retry: () async -> Void

    @Environment(\.openURL) private var openURL
    @State private var isRetrying = false

    var body: some View {
        let text = FailureText(failure)
        ContentUnavailableView {
            Label(text.title, systemImage: text.systemImage)
        } description: {
            Text(text.message)
        } actions: {
            if FailureText.needsSettings(failure) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.brandProminent)
            } else {
                Button {
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                    } else {
                        Text("Try Again")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRetrying)
            }
        }
    }
}

extension View {
    /// Shows `failure` in an alert while it is set.
    func failureAlert(_ failure: Binding<Failure?>) -> some View {
        alert(
            failure.wrappedValue.map { FailureText($0).title } ?? "",
            isPresented: Binding(
                get: { failure.wrappedValue != nil },
                set: { if !$0 { failure.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let value = failure.wrappedValue {
                Text(FailureText(value).message)
            }
        }
    }
}

/// The app's primary button: brand yellow with dark text, legible in light and dark mode.
struct BrandProminentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .foregroundStyle(Color.brandForeground)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.brand)
    }
}

extension PrimitiveButtonStyle where Self == BrandProminentButtonStyle {
    static var brandProminent: BrandProminentButtonStyle { BrandProminentButtonStyle() }
}
