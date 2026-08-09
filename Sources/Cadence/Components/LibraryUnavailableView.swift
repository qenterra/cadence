import AppKit
import SwiftUI

struct LibraryUnavailableView: View {
    let failure: LibrarySessionFailure
    let retry: () -> Void
    let locate: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(
                "Cadence Library Unavailable",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            VStack(spacing: 12) {
                Text(summary)
                DisclosureGroup("Technical Details") {
                    Text(failure.message)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 420)
            }
        } actions: {
            HStack(spacing: 12) {
                if canRetry {
                    Button("Retry", action: retry)
                        .buttonStyle(.borderedProminent)
                }
                if let locate {
                    if canRetry {
                        Button("Locate Library…", action: locate)
                            .buttonStyle(.bordered)
                    } else {
                        Button("Locate Library…", action: locate)
                            .buttonStyle(.borderedProminent)
                    }
                }
                if let revealURL = failure.revealURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [revealURL]
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
    }

    private var summary: String {
        switch failure.kind {
        case .locationUnavailable:
            "Cadence could not access the saved library location."
        case .staleBookmark:
            "Cadence needs permission to access the library again."
        case .identityMismatch:
            "The selected folder contains a different Cadence library."
        case .blockingPackageFile:
            "A file is blocking the Cadence.library package."
        case .missingMetadataStore:
            "Cadence.library is missing its metadata store."
        case .openFailed:
            "Cadence could not open the managed library."
        case .recoveryFailed:
            "Cadence could not finish recovering the managed library."
        }
    }

    private var canRetry: Bool {
        switch failure.kind {
        case .locationUnavailable, .staleBookmark, .identityMismatch:
            false
        case .blockingPackageFile, .missingMetadataStore, .openFailed, .recoveryFailed:
            true
        }
    }
}
