import SwiftUI

struct LyricsPanel: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        Group {
            if let (track, document) = lyricContext {
                switch document.timingStatus {
                case .synchronized:
                    SynchronizedLyricsView(
                        model: model,
                        track: track,
                        document: document
                    )
                case .partiallySynchronized, .unsynchronized:
                    StaticLyricsView(
                        model: model,
                        document: document
                    )
                case .missing:
                    MissingLyricsView(model: model)
                }
            } else {
                MissingLyricsView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyricContext: (TrackPreview, LyricDocument)? {
        guard
            let track = model.currentTrack,
            let document = model.lyricDocuments[track.id]
        else {
            return nil
        }
        return (track, document)
    }
}
