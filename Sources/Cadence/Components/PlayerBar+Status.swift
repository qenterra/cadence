import SwiftUI

extension PlayerBar {
    @ViewBuilder
    var emptyPlaybackGuidance: some View {
        if model.librarySession.store.catalogCounts.liveTrackCount == 0 {
            Button {
                model.requestNavigationDestination(.importMusic)
            } label: {
                Label("Import Music", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Import music to start listening")
        } else {
            Label("Select a Track", systemImage: "music.note")
                .foregroundStyle(.secondary)
                .help("Choose a track from the library to start playback")
        }
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
