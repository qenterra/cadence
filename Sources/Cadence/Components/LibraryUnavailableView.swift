import SwiftUI

struct LibraryUnavailableView: View {
    let failure: LibrarySessionFailure

    var body: some View {
        ContentUnavailableView {
            Label(
                "Cadence Library Unavailable",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(failure.message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
    }
}
