import QenTerraMediaComponents
import SwiftUI

enum NowPlayingPanelPresentation {
    static let showsRedundantHeaderTitle = false
    static let showsUpNextSectionTitle = false
}

extension ProductionNowPlayingView {
    @ViewBuilder
    var playbackFailure: some View {
        if let failure = model.playbackCoordinator?.state.failure {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    failure.message,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Retry") {
                        model.retryPlaybackFailure()
                    }
                    Button("Skip") {
                        model.skipPlaybackFailure()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Playback error: \(failure.message)")
        }
    }

    @ViewBuilder
    var audioQuality: some View {
        let badges = NowPlayingMetadataBadges.resolve(
            audioPath: model.playbackCoordinator?.state.audioPath,
            currentTrackID: track.id,
            lyricDocument: displayedLyricDocument,
            showsTechnicalInformation: showsTechnicalInformation
        )
        if badges.audioQuality != nil || badges.showsSynchronizedLyrics {
            HStack(spacing: 8) {
                if let presentation = badges.audioQuality {
                    Button {
                        isAudioDetailsPresented.toggle()
                    } label: {
                        MediaMetadataBadge(
                            label: presentation.badge,
                            symbolName: "waveform"
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Show Audio Details")
                    .accessibilityHint(
                        "Shows format, renderer, and output details"
                    )
                    .popover(
                        isPresented: $isAudioDetailsPresented,
                        arrowEdge: .bottom
                    ) {
                        AudioDetailsPopover(presentation: presentation)
                    }
                }

                if badges.showsSynchronizedLyrics {
                    MediaMetadataBadge(
                        label: "LRC",
                        accessibilityLabel: "Synchronized lyrics"
                    )
                    .help("Synchronized lyrics available")
                }
            }
        }
    }

    var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", systemImage: "chevron.backward") {
                    model.dismissNowPlaying()
                }
                .labelStyle(.titleAndIcon)
                .keyboardShortcut("[", modifiers: .command)

                Spacer()
                NowPlayingPanelPicker(model: model)
            }
            .padding(.horizontal, 28)
            .frame(height: 76)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            switch model.selectedNowPlayingPanel {
            case .lyrics:
                ProductionLyricsPanel(model: model, track: track)
            case .queue:
                ProductionPlaybackQueuePanel(model: model)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
