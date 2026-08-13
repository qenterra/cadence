import SwiftUI

extension PlayerBar {
    @ViewBuilder
    var emptyPlaybackGuidance: some View {
        let presentation = PlayerBarEmptyPresentation(
            libraryTrackCount: model.librarySession.store.catalogCounts.liveTrackCount
        )
        Label(presentation.title, systemImage: presentation.symbolName)
            .foregroundStyle(CadenceTheme.playerMetadata)
            .help(presentation.title)
    }

    @ViewBuilder
    var playbackFailureMenu: some View {
        if let failure = model.playbackCoordinator?.state.failure {
            Menu {
                Text(failure.message)
                Divider()
                Button("Retry", systemImage: "arrow.clockwise") {
                    model.retryPlaybackFailure()
                }
                Button("Skip", systemImage: "forward.end") {
                    model.skipPlaybackFailure()
                }
            } label: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help(failure.message)
            .accessibilityLabel("Playback error: \(failure.message)")
        }
    }

    var audioOutputMenu: some View {
        AirPlayRoutePicker(
            player: model.playbackCoordinator?.airPlayPlayer
        )
        .frame(width: 34, height: 34)
        .help("Audio Output: \(model.playbackOutputRoute.name)")
        .accessibilityLabel(
            "Audio Output, \(model.playbackOutputRoute.name)"
        )
    }
}
