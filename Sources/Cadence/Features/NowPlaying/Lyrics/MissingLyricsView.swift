import SwiftUI

struct MissingLyricsView: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        ContentUnavailableView {
            Label("No Lyrics", systemImage: "quote.bubble")
        } description: {
            Text("Add line-level lyrics or import an LRC preview for this track.")
        } actions: {
            HStack {
                Button("Add Lyrics") {
                    model.presentLyricsEditor()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                Button("Import .lrc") {
                    model.presentLyricsEditor()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
