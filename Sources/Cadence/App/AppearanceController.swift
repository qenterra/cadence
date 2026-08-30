import AppKit

@MainActor
final class AppearanceController {
    func apply(
        _ choice: CadenceAppearance,
        application: NSApplication = .shared,
        windows: [NSWindow]? = nil
    ) {
        application.appearance = choice.appKitAppearance
        for window in allWindows(
            startingAt: windows ?? application.windows
        ) {
            window.appearanceSource = application
            window.appearance = nil
            window.contentView?.superview?.needsDisplay = true
            window.invalidateShadow()
        }
    }

    private func allWindows(
        startingAt roots: [NSWindow]
    ) -> [NSWindow] {
        var result: [NSWindow] = []
        var visited = Set<ObjectIdentifier>()
        var pending = roots

        while let window = pending.popLast() {
            guard visited.insert(ObjectIdentifier(window)).inserted else {
                continue
            }
            result.append(window)
            pending.append(contentsOf: window.childWindows ?? [])
            if let sheet = window.attachedSheet {
                pending.append(sheet)
            }
        }
        return result
    }
}
