import AppKit
import QenTerraComponents
import SwiftUI

struct LibraryUnavailableView: View {
    let failure: LibrarySessionFailure
    let retry: () -> Void
    let locate: (() -> Void)?

    var body: some View {
        ContentStateView(
            state: .unavailable(
                title: "Cadence Library Unavailable",
                message: summary
            ),
            symbolName: "exclamationmark.triangle",
            actions: actions,
            presentation: .nativeUnavailable
        ) {
            DisclosureGroup("Technical Details") {
                Text(failure.message)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
    }

    private var summary: String {
        switch failure.kind {
        case .locationUnavailable:
            String(localized: "Cadence could not access the saved library location.")
        case .configurationUnavailable:
            String(localized: "Cadence could not read the saved library location settings.")
        case .staleBookmark:
            String(localized: "Cadence needs permission to access the library again.")
        case .identityMismatch:
            String(localized: "The selected folder contains a different Cadence library.")
        case .blockingPackageFile:
            String(localized: "A file is blocking the Cadence folder.")
        case .missingMetadataStore:
            String(localized: "The Cadence folder is missing its metadata store.")
        case .unreadableIdentity:
            String(localized: "The Cadence folder has an unreadable identity record.")
        case .openFailed:
            String(localized: "Cadence could not open the managed library.")
        case .recoveryFailed:
            String(localized: "Cadence could not finish recovering the managed library.")
        }
    }

    private var canRetry: Bool {
        switch failure.kind {
        case .locationUnavailable, .configurationUnavailable,
             .staleBookmark, .identityMismatch:
            false
        case .blockingPackageFile, .missingMetadataStore, .unreadableIdentity,
             .openFailed, .recoveryFailed:
            true
        }
    }

    private var actions: [PresentationAction] {
        var result: [PresentationAction] = []
        if canRetry {
            result.append(
                PresentationAction(
                    title: failure.kind == .recoveryFailed ? "Repair" : "Retry",
                    style: .primary,
                    handler: retry
                )
            )
        }
        if let locate {
            result.append(
                PresentationAction(
                    title: "Locate Library…",
                    style: canRetry ? .secondary : .primary,
                    handler: locate
                )
            )
        }
        if let revealURL = failure.revealURL {
            result.append(
                PresentationAction(
                    title: "Reveal in Finder",
                    style: .plain
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                }
            )
        }
        return result
    }
}
