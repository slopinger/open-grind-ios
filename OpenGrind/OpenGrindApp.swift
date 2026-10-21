import OpenGrindKit
import SwiftUI

@main
struct OpenGrindApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.imagePipeline, model.images)
        }
        .onChange(of: scenePhase) { _, phase in
            // Inactive, e.g. under Control Center or an alert, is still in the foreground.
            if phase != .inactive { model.account.setActive(phase == .active) }
        }
    }
}

/// Chooses between the welcome screen and the signed-in app.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let failure = model.startupFailure {
                StartupFailureView(failure: failure)
            } else if let session = model.account.session {
                MainTabView()
                    .environment(session)
                    .id(ObjectIdentifier(session))
            } else {
                WelcomeView()
            }
        }
        .animation(.default, value: model.account.session.map(ObjectIdentifier.init))
    }
}

/// Shown when the network layer cannot be set up at all.
private struct StartupFailureView: View {
    let failure: Failure
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Open Grind Can't Start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(
                "The secure connection to Grindr couldn't be set up on this device. You can still try the demo."
            )
        } actions: {
            Button("Try the Demo") { model.startDemo() }
                .buttonStyle(.brandProminent)
        }
    }
}
