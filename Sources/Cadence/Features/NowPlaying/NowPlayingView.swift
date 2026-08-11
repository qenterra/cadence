import SwiftUI

struct NowPlayingView: View {
    @Bindable var model: CadenceAppModel
    let cadenceModeSession: CadenceModeSession

    var body: some View {
        Group {
            if let track = model.currentPlaybackTrack {
                ProductionNowPlayingView(
                    model: model,
                    track: track,
                    cadenceModeSession: cadenceModeSession
                )
            } else {
                ContentUnavailableView {
                    Label("Nothing Playing", systemImage: "music.note")
                } description: {
                    Text("Start a track to open Now Playing.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CadenceTheme.contentBackground)
        .onExitCommand {
            model.dismissNowPlaying()
        }
    }
}
