import AppKit

@MainActor
final class CadenceApplicationDelegate: NSObject, NSApplicationDelegate {
    typealias OpenHandler = ([URL]) -> Void

    private var openHandler: OpenHandler?
    private var pendingBatches: [[URL]] = []
    private var terminationHandler: (() -> Void)?

    func application(
        _: NSApplication,
        open urls: [URL]
    ) {
        receiveOpenURLs(urls)
    }

    func applicationWillTerminate(_: Notification) {
        terminationHandler?()
    }

    func receiveOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        guard let openHandler else {
            pendingBatches.append(urls)
            return
        }
        openHandler(urls)
    }

    func connect(_ handler: @escaping OpenHandler) {
        openHandler = handler
        let batches = pendingBatches
        pendingBatches = []
        batches.forEach(handler)
    }

    func onTermination(_ handler: @escaping () -> Void) {
        terminationHandler = handler
    }
}
