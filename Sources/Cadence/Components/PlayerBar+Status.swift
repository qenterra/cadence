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

    var qualityProfileMenu: some View {
        Button {
            isQualityProfilePresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .symbolEffect(
                    .pulse,
                    options: .nonRepeating,
                    isActive: isQualityProfilePresented
                )
                .foregroundStyle(
                    isQualityProfilePresented ? .primary : .secondary
                )
                .frame(width: 34, height: 34)
                .background {
                    if isQualityProfilePresented {
                        RoundedRectangle(
                            cornerRadius: CadenceTheme.radiusControl,
                            style: .continuous
                        )
                        .fill(CadenceTheme.selectionFill)
                    }
                }
        }
        .buttonStyle(CadenceRowButtonStyle())
        .popover(
            isPresented: $isQualityProfilePresented,
            arrowEdge: .bottom
        ) {
            qualityProfilePopover
        }
        .help("Quality Profile: \(model.qualityProfile.title)")
        .accessibilityLabel(
            "Quality Profile, \(model.qualityProfile.title)"
        )
    }

    var qualityProfilePopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quality Profile")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(AudioQualityProfile.allCases) { profile in
                Button {
                    model.selectQualityProfile(profile)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .opacity(model.qualityProfile == profile ? 1 : 0)
                            .frame(width: 14)
                        Text(profile.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(CadenceMenuRowButtonStyle())
            }

            Divider()
                .padding(.vertical, 4)

            Toggle(
                "Spatialize Stereo",
                isOn: $model.isStereoSpatializationEnabled
            )
            .disabled(model.qualityProfile != .immersive)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .padding(6)
        .frame(width: 220)
    }
}
