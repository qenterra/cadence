import AppKit
@testable import Cadence
import Testing

@MainActor
struct AppearanceControllerTests {
    @Test("System appearance clears overrides on every open window immediately")
    func systemAppearanceClearsOverrides() {
        let controller = AppearanceController()
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let nestedView = NSView(frame: rootView.bounds)
        rootView.addSubview(nestedView)
        let window = NSWindow(
            contentRect: rootView.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = rootView
        window.appearance = NSAppearance(named: .darkAqua)

        controller.apply(.system, to: [window])

        #expect(window.appearance == nil)
        #expect(rootView.needsDisplay)
        #expect(nestedView.needsDisplay)
    }

    @Test("Explicit appearances reach attached sheets")
    func explicitAppearanceReachesSheets() {
        let controller = AppearanceController()
        let parent = NSWindow()
        let sheet = NSWindow()
        parent.addChildWindow(sheet, ordered: .above)

        controller.apply(.light, to: [parent])

        #expect(parent.appearance?.name == .aqua)
        #expect(sheet.appearance?.name == .aqua)
    }
}
