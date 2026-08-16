import AppKit
@testable import Cadence
import Foundation
import Testing

@MainActor
struct LibraryFolderIconControllerTests {
    @Test("Cadence applies the appearance-specific app icon to its folder")
    func appliesAppearanceSpecificIcon() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Folder-Icon-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }

        let workspace = FolderIconWorkspaceStub(result: true)
        let source = FolderIconSourceStub()
        let controller = LibraryFolderIconController(
            workspace: workspace,
            source: source
        )

        #expect(controller.applyIcon(to: folder, appearance: .dark))
        #expect(source.requestedAppearances == [.dark])
        #expect(workspace.appliedURLs == [folder])
    }

    @Test("Folder decoration failure is non-fatal and missing folders are ignored")
    func failureIsNonFatal() {
        let workspace = FolderIconWorkspaceStub(result: false)
        let source = FolderIconSourceStub()
        let controller = LibraryFolderIconController(
            workspace: workspace,
            source: source
        )
        let missing = URL(filePath: "/tmp/Cadence-Missing-\(UUID().uuidString)")

        #expect(!controller.applyIcon(to: missing, appearance: .light))
        #expect(workspace.appliedURLs.isEmpty)
    }
}

@MainActor
private final class FolderIconWorkspaceStub: LibraryFolderIconApplying {
    let result: Bool
    private(set) var appliedURLs: [URL] = []

    init(result: Bool) {
        self.result = result
    }

    func setIcon(
        _: NSImage,
        forFile url: URL
    ) -> Bool {
        appliedURLs.append(url)
        return result
    }
}

@MainActor
private final class FolderIconSourceStub: LibraryFolderIconSourcing {
    private(set) var requestedAppearances: [LibraryFolderAppearance] = []

    func icon(
        for appearance: LibraryFolderAppearance
    ) -> NSImage? {
        requestedAppearances.append(appearance)
        return NSImage(size: NSSize(width: 32, height: 32))
    }
}
