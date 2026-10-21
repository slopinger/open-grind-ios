/// Runs an action once a burst of calls has settled: each call cancels the
/// one before.
@MainActor
final class Debouncer {
    private let delay: Duration
    private var pending: Task<Void, Never>?

    init(_ delay: Duration) {
        self.delay = delay
    }

    func schedule(_ action: @escaping @MainActor () async -> Void) {
        pending?.cancel()
        pending = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
