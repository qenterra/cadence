import AppKit
import SwiftUI

struct LibraryUnavailableView: View {
    let failure: LibrarySessionFailure
    let retry: () -> Void

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
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
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
            "Cadence could not resolve the Music folder."
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
}
