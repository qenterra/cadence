import AppKit

struct AppearanceRefreshIdentity: Hashable, Sendable {
    let rawValue: String
}

@MainActor
final class AppearanceController {
    func apply(
        _ choice: CadenceAppearance,
        application: NSApplication = .shared
    ) {
        application.appearance = choice.appKitAppearance
        apply(choice, to: application.windows)
    }

    func apply(
        _ choice: CadenceAppearance,
        to windows: [NSWindow]
    ) {
        let appearance = choice.appKitAppearance
        for window in allWindows(startingAt: windows) {
            window.appearance = appearance
            refresh(view: window.contentView)
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

    private func refresh(
        view: NSView?
    ) {
        guard let view else {
            return
        }
        view.needsDisplay = true
        view.needsLayout = true
        view.invalidateIntrinsicContentSize()
        for subview in view.subviews {
            refresh(view: subview)
        }
    }
}
