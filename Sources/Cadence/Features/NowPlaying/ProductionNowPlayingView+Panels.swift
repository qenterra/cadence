import SwiftUI

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
        if let path = model.playbackCoordinator?.state.audioPath {
            let presentation = AudioQualityPresentation(path: path)
            Button {
                isAudioDetailsPresented.toggle()
            } label: {
                Label(presentation.badge, systemImage: "waveform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(CadenceTheme.subduedFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Show Audio Details")
            .accessibilityHint("Shows format, renderer, and output details")
            .popover(isPresented: $isAudioDetailsPresented, arrowEdge: .bottom) {
                AudioDetailsPopover(presentation: presentation)
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

                Text(model.selectedNowPlayingPanel.title)
                    .font(.title2.weight(.semibold))
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
