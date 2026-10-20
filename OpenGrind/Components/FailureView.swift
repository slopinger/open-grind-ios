import OpenGrindKit
import SwiftUI

/// A full-screen explanation of why content could not load, with a way out.
struct FailureView: View {
    /// Another way out than trying again, such as going back to your own location.
    struct Recovery {
        var title: LocalizedStringKey
        var action: () -> Void
    }

    let failure: Failure
    let retry: () async -> Void
    var recovery: Recovery?

    @Environment(\.openURL) private var openURL
    @State private var isRetrying = false

    var body: some View {
        let text = FailureText(failure)
        ContentUnavailableView {
            Label(text.title, systemImage: text.systemImage)
        } description: {
            Text(text.message)
        } actions: {
            if let recovery {
                Button(recovery.title, action: recovery.action)
                    .buttonStyle(.bordered)
            }
            if FailureText.needsSettings(failure) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.brandProminent)
            } else if FailureText.canRetry(failure) {
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

/// A spinner filling the screen while content loads.
struct LoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Content that loads: a spinner, or the failure with a way to try again, while
/// there is nothing to show yet; otherwise the content, which keeps showing
/// through reloads and failed refreshes.
struct LoadStateView<Content: View>: View {
    let state: LoadState
    let isEmpty: Bool
    let retry: () async -> Void
    let recovery: FailureView.Recovery?
    let content: Content

    init(
        _ state: LoadState, isEmpty: Bool, retry: @escaping () async -> Void, recovery: FailureView.Recovery? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.state = state
        self.isEmpty = isEmpty
        self.retry = retry
        self.recovery = recovery
        self.content = content()
    }

    var body: some View {
        switch state {
        case .idle,
            .loading where isEmpty:
            LoadingView()
        case .failed(let failure) where isEmpty:
            FailureView(failure: failure, retry: retry, recovery: recovery)
        default:
            content
        }
    }
}

extension View {
    /// Shows `failure` in an alert while it is set.
    func failureAlert(_ failure: Binding<Failure?>) -> some View {
        alert(
            failure.wrappedValue.map { FailureText($0).title } ?? "",
            isPresented: failure.isPresent()
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
