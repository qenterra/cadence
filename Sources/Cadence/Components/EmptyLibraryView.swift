import SwiftUI

struct EmptyLibraryView: View {
    let title: String
    let description: String
    let importAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "music.note")
        } description: {
            Text(description)
        } actions: {
            Button("Import Music", action: importAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
