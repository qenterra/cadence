import AppKit
import SwiftUI

enum LibraryFolderAppearance: Equatable, Sendable {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
protocol LibraryFolderIconApplying: AnyObject {
    func setIcon(
        _ image: NSImage,
        forFile url: URL
    ) -> Bool
}

@MainActor
protocol LibraryFolderIconSourcing: AnyObject {
    func icon(
        for appearance: LibraryFolderAppearance
    ) -> NSImage?
}

@MainActor
final class WorkspaceLibraryFolderIconAdapter: LibraryFolderIconApplying {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func setIcon(
        _ image: NSImage,
        forFile url: URL
    ) -> Bool {
        workspace.setIcon(image, forFile: url.path, options: [])
    }
}

@MainActor
final class ApplicationLibraryFolderIconSource: LibraryFolderIconSourcing {
    private let workspace: NSWorkspace
    private let bundle: Bundle

    init(
        workspace: NSWorkspace = .shared,
        bundle: Bundle = .main
    ) {
        self.workspace = workspace
        self.bundle = bundle
    }

    func icon(
        for appearance: LibraryFolderAppearance
    ) -> NSImage? {
        let source = workspace.icon(forFile: bundle.bundlePath)
        source.size = NSSize(width: 512, height: 512)
        guard let drawingAppearance = appearance.appKitAppearance else {
            return source
        }

        let rendered = NSImage(size: source.size)
        drawingAppearance.performAsCurrentDrawingAppearance {
            rendered.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(
                in: NSRect(origin: .zero, size: rendered.size),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            rendered.unlockFocus()
        }
        return rendered
    }
}

@MainActor
final class LibraryFolderIconController {
    private let fileManager: FileManager
    private let workspace: any LibraryFolderIconApplying
    private let source: any LibraryFolderIconSourcing

    init(
        fileManager: FileManager = .default,
        workspace: any LibraryFolderIconApplying =
            WorkspaceLibraryFolderIconAdapter(),
        source: any LibraryFolderIconSourcing =
            ApplicationLibraryFolderIconSource()
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
        self.source = source
    }

    @discardableResult
    func applyIcon(
        to folderURL: URL,
        appearance: LibraryFolderAppearance
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(
                atPath: folderURL.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue,
            let icon = source.icon(for: appearance)
        else {
            return false
        }
        return workspace.setIcon(icon, forFile: folderURL)
    }
}
