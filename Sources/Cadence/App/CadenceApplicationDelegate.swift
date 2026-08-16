import AppKit

@MainActor
final class CadenceApplicationDelegate: NSObject, NSApplicationDelegate {
    typealias OpenHandler = ([URL]) -> Void

    private var openHandler: OpenHandler?
    private var pendingBatches: [[URL]] = []
    private var terminationHandler: (() -> Void)?

    /// AppKit supplies document URLs as one ordered batch. Cadence preserves
    /// that batch so Finder selections become one transient playback queue.
    func application(
        _: NSApplication,
        open urls: [URL]
    ) {
        receiveOpenURLs(urls)
    }

    func applicationWillTerminate(_: Notification) {
        terminationHandler?()
    }

    func connect(_ handler: @escaping OpenHandler) {
        openHandler = handler
        let batches = pendingBatches
        pendingBatches = []
        batches.forEach(handler)
    }

    func connect(
        instanceCoordinator: CadenceInstanceCoordinator,
        handler: @escaping OpenHandler,
        terminateDuplicate: @escaping () -> Void
    ) {
        openHandler = { urls in
            instanceCoordinator.route(urls: urls)
        }
        instanceCoordinator.connect(handler)
        let batches = pendingBatches
        pendingBatches = []
        batches.forEach { instanceCoordinator.route(urls: $0) }

        if instanceCoordinator.claim() == .duplicate {
            instanceCoordinator.activateOwner()
            terminateDuplicate()
        }
    }

    func onTermination(_ handler: @escaping () -> Void) {
        terminationHandler = handler
    }

    private func receiveOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        guard let openHandler else {
            pendingBatches.append(urls)
            return
        }
        openHandler(urls)
    }
}
