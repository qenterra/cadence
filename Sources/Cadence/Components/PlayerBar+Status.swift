import AppKit
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
        Menu {
            Section("Current Output") {
                Label(
                    model.playbackOutputRoute.name,
                    systemImage: audioRouteSymbol
                )
                Text(model.playbackPathStatus)
            }
            Divider()
            Button("Open Sound Settings…", systemImage: "gear") {
                openSoundSettings()
            }
        } label: {
            Image(systemName: "airplayaudio")
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .help("Audio Output: \(model.playbackOutputRoute.name)")
        .accessibilityLabel(
            "Audio Output, \(model.playbackOutputRoute.name)"
        )
    }

    private var audioRouteSymbol: String {
        switch model.playbackOutputRoute.transport {
        case .airPlay:
            "airplayaudio"
        case .bluetooth:
            "wave.3.right"
        case .builtIn:
            "laptopcomputer"
        case .wired:
            "headphones"
        case .unknown:
            "speaker.wave.2"
        }
    }

    private func openSoundSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Sound-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
