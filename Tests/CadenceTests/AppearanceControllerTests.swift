import AppKit
@testable import Cadence
import Testing

@MainActor
struct AppearanceControllerTests {
    @Test("Appearance is applied once at app scope and windows inherit it")
    func appearanceUsesApplicationScope() {
        let controller = AppearanceController()
        let window = NSWindow()
        let staleAppearanceSource = NSView()
        staleAppearanceSource.appearance = NSAppearance(named: .darkAqua)
        window.appearanceSource = staleAppearanceSource
        window.appearance = NSAppearance(named: .darkAqua)
        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }

        controller.apply(
            .light,
            application: NSApp,
            windows: [window]
        )

        #expect(NSApp.appearance?.name == .aqua)
        #expect(window.appearanceSource === NSApp)
        #expect(window.appearance == nil)
    }

    @Test("System appearance restores application-owned window chrome")
    func systemAppearanceRestoresWindowInheritance() {
        let controller = AppearanceController()
        let window = NSWindow()
        let staleAppearanceSource = NSView()
        staleAppearanceSource.appearance = NSAppearance(named: .aqua)
        window.appearanceSource = staleAppearanceSource
        window.appearance = NSAppearance(named: .darkAqua)
        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }

        controller.apply(
            .system,
            application: NSApp,
            windows: [window]
        )

        #expect(NSApp.appearance == nil)
        #expect(window.appearanceSource === NSApp)
        #expect(window.appearance == nil)
    }

    @Test("Inherited appearance also releases stale child-window overrides")
    func inheritedAppearanceReachesChildWindows() {
        let controller = AppearanceController()
        let parent = NSWindow()
        let sheet = NSWindow()
        parent.addChildWindow(sheet, ordered: .above)
        parent.appearance = NSAppearance(named: .aqua)
        sheet.appearance = NSAppearance(named: .darkAqua)
        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }

        controller.apply(
            .dark,
            application: NSApp,
            windows: [parent]
        )

        #expect(NSApp.appearance?.name == .darkAqua)
        #expect(parent.appearance == nil)
        #expect(sheet.appearance == nil)
    }
}
