import SwiftUI

struct SettingsPlaybackView: View {
    @Bindable var model: CadenceAppModel

    @AppStorage(CadencePreferences.Keys.playbackTimeDisplay)
    private var timeDisplayRawValue = PlaybackTimeDisplayMode.elapsed.rawValue
    @AppStorage(CadencePreferences.Keys.restoresQueue)
    private var restoresQueue = true
    @AppStorage(CadencePreferences.Keys.previousTrackBehavior)
    private var previousBehaviorRawValue =
        PreviousTrackBehavior.restartCurrent.rawValue
    @AppStorage(CadencePreferences.Keys.seekInterval)
    private var seekIntervalRawValue = SeekInterval.seconds15.rawValue
    @AppStorage(CadencePreferences.Keys.volumeNormalization)
    private var normalizationRawValue = VolumeNormalizationMode.off.rawValue
    @AppStorage(CadencePreferences.Keys.volumeAdjustmentStep)
    private var volumeAdjustmentStepRawValue =
        VolumeAdjustmentStep.percent5.rawValue
    @AppStorage(CadencePreferences.Keys.crossfadeDuration)
    private var crossfadeDurationRawValue = CrossfadeDuration.off.rawValue
    @AppStorage(CadencePreferences.Keys.resumesAfterRouteRecovery)
    private var resumesAfterRouteRecovery = true
    @AppStorage(CadencePreferences.Keys.preventsDisplaySleep)
    private var preventsDisplaySleep = false
    @AppStorage(CadencePreferences.Keys.lyricsTextSize)
    private var lyricsTextSizeRawValue = LyricsTextSize.standard.rawValue
    @AppStorage(CadencePreferences.Keys.showsTechnicalInformation)
    private var showsTechnicalInformation = true

    @AppStorage(CadenceModePreferences.isEnabledKey)
    private var isCadenceModeEnabled = CadenceModeOptions.default.isEnabled
    @AppStorage(CadenceModePreferences.reactsToBassKey)
    private var cadenceModeReactsToBass = CadenceModeOptions.default.reactsToBass
    @AppStorage(CadenceModePreferences.showsLyricsKey)
    private var cadenceModeShowsLyrics = CadenceModeOptions.default.showsLyrics
    @AppStorage(CadenceModePreferences.showsTrackInformationKey)
    private var cadenceModeShowsTrackInformation =
        CadenceModeOptions.default.showsTrackInformation
    @AppStorage(CadenceModePreferences.staysActiveKey)
    private var staysInCadenceMode = CadenceModeOptions.default.staysActive

    var body: some View {
        playbackBehaviorCard
        nowPlayingCard
        cadenceModeCard
    }

    private var playbackBehaviorCard: some View {
        SettingsCard(title: "Playback", symbol: "play.circle") {
            SettingsToggleRow("Restore Queue", isOn: $restoresQueue)

            Picker("Previous Button", selection: previousBehaviorBinding) {
                ForEach(PreviousTrackBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }

            Picker("Seek Step", selection: seekIntervalBinding) {
                ForEach(SeekInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }

            Picker("Volume Step", selection: volumeAdjustmentStepBinding) {
                ForEach(VolumeAdjustmentStep.allCases) { step in
                    Text(step.title).tag(step)
                }
            }

            Picker("Volume Normalization", selection: normalizationBinding) {
                ForEach(VolumeNormalizationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Crossfade", selection: crossfadeDurationBinding) {
                ForEach(CrossfadeDuration.allCases) { duration in
                    Text(duration.title).tag(duration)
                }
            }

            SettingsToggleRow(
                "Resume After Output Reconnects",
                isOn: $resumesAfterRouteRecovery
            )

            SettingsToggleRow(
                "Prevent Display Sleep While Playing",
                isOn: $preventsDisplaySleep
            )

            Text(
                """
                A restored queue opens paused. Crossfade applies only between normally advancing tracks. \
                Track ReplayGain is used only when the file provides it.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: seekIntervalRawValue) {
            model.refreshPlaybackPreferences()
        }
        .onChange(of: normalizationRawValue) {
            model.refreshPlaybackPreferences()
        }
        .onChange(of: volumeAdjustmentStepRawValue) {
            model.refreshPlaybackPreferences()
        }
        .onChange(of: crossfadeDurationRawValue) {
            model.refreshPlaybackPreferences()
        }
        .onChange(of: restoresQueue) {
            model.refreshPlaybackPreferences()
        }
    }

    private var nowPlayingCard: some View {
        SettingsCard(title: "Now Playing", symbol: "music.note.list") {
            Picker("Time Display", selection: timeDisplayBinding) {
                ForEach(PlaybackTimeDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Lyrics Text Size", selection: lyricsTextSizeBinding) {
                ForEach(LyricsTextSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }

            SettingsToggleRow(
                "Show Technical Audio Information",
                isOn: $showsTechnicalInformation
            )
        }
    }

    private var cadenceModeCard: some View {
        SettingsCard(title: "Cadence Mode", symbol: "waveform") {
            SettingsToggleRow(
                "Enable Cadence Mode",
                isOn: $isCadenceModeEnabled
            )
            SettingsToggleRow(
                "React to Bass",
                isOn: $cadenceModeReactsToBass
            )
            .disabled(!isCadenceModeEnabled)
            SettingsToggleRow(
                "Show Synchronized Lyrics",
                isOn: $cadenceModeShowsLyrics
            )
            .disabled(!isCadenceModeEnabled)
            SettingsToggleRow(
                "Show Track Information",
                isOn: $cadenceModeShowsTrackInformation
            )
            .disabled(!isCadenceModeEnabled)
            SettingsToggleRow(
                "Stay in Cadence Mode",
                isOn: $staysInCadenceMode
            )
            .disabled(!isCadenceModeEnabled)

            Text(cadenceModeHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cadenceModeHelpText: LocalizedStringKey {
        guard isCadenceModeEnabled else {
            return "The Z + X shortcut, visual effects, and direct entry are disabled."
        }
        return staysInCadenceMode
            ? "Cadence Mode stays open until you leave it."
            : "Cadence Mode closes after ten seconds without input."
    }

    private var timeDisplayBinding: Binding<PlaybackTimeDisplayMode> {
        rawBinding(
            $timeDisplayRawValue,
            fallback: PlaybackTimeDisplayMode.elapsed
        )
    }

    private var previousBehaviorBinding: Binding<PreviousTrackBehavior> {
        rawBinding(
            $previousBehaviorRawValue,
            fallback: PreviousTrackBehavior.restartCurrent
        )
    }

    private var seekIntervalBinding: Binding<SeekInterval> {
        Binding(
            get: {
                SeekInterval(rawValue: seekIntervalRawValue) ?? .seconds15
            },
            set: { seekIntervalRawValue = $0.rawValue }
        )
    }

    private var normalizationBinding: Binding<VolumeNormalizationMode> {
        rawBinding(
            $normalizationRawValue,
            fallback: VolumeNormalizationMode.off
        )
    }

    private var volumeAdjustmentStepBinding: Binding<VolumeAdjustmentStep> {
        Binding(
            get: {
                VolumeAdjustmentStep(rawValue: volumeAdjustmentStepRawValue)
                    ?? .percent5
            },
            set: { volumeAdjustmentStepRawValue = $0.rawValue }
        )
    }

    private var crossfadeDurationBinding: Binding<CrossfadeDuration> {
        Binding(
            get: {
                CrossfadeDuration(rawValue: crossfadeDurationRawValue) ?? .off
            },
            set: { crossfadeDurationRawValue = $0.rawValue }
        )
    }

    private var lyricsTextSizeBinding: Binding<LyricsTextSize> {
        rawBinding(
            $lyricsTextSizeRawValue,
            fallback: LyricsTextSize.standard
        )
    }

    private func rawBinding<Value: RawRepresentable>(
        _ rawValue: Binding<String>,
        fallback: Value
    ) -> Binding<Value> where Value.RawValue == String {
        Binding(
            get: { Value(rawValue: rawValue.wrappedValue) ?? fallback },
            set: { rawValue.wrappedValue = $0.rawValue }
        )
    }
}
