import SwiftUI

enum LyricsEditorClockPresentation {
    static func resolve(
        stateTime: TimeInterval,
        presentationTime: TimeInterval,
        isPlaying: Bool
    ) -> String {
        LyricTimestampFormatter.display(
            isPlaying ? presentationTime : stateTime
        )
    }
}

struct TapToSyncPanel: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) private var undoManager
    @FocusState private var ownsKeyboard: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tap to Sync")
                .font(.title2.weight(.semibold))

            if let track = model.currentTrack {
                Text("\(track.title) · \(track.durationText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
            } else if let track = model.currentPlaybackTrack {
                Text(
                    "\(track.title) · "
                        + LyricTimestampFormatter.display(track.duration)
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            }

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
                .padding(.vertical, 22)

            Text("Current line")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Text(activeLine?.text.nonEmpty ?? "Select a lyric line")
                .font(.title3.weight(.medium))
                .foregroundStyle(activeLine == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline) {
                playbackClock

                Spacer()

                Text(activeLinePosition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                model.stampActiveLyricLine(undoManager: undoManager)
                ownsKeyboard = true
            } label: {
                Label("Stamp Current Line", systemImage: "return")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(activeLine == nil)
            .padding(.top, 18)

            HStack {
                Button("Previous Line", systemImage: "arrow.up") {
                    model.moveActiveLyricLine(by: -1)
                    ownsKeyboard = true
                }
                Button("Next Line", systemImage: "arrow.down") {
                    model.moveActiveLyricLine(by: 1)
                    ownsKeyboard = true
                }
            }
            .buttonStyle(.borderless)
            .padding(.top, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                keyboardHint("Return", "stamp and advance")
                keyboardHint("Space", "play or pause")
                keyboardHint("↑ / ↓", "change active line")
            }
            .padding(.top, 24)

            Text(
                ownsKeyboard
                    ? "Keyboard capture active"
                    : "Click this panel to enable sync shortcuts"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 14)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CadenceTheme.secondarySurface.opacity(0.72))
        .contentShape(Rectangle())
        .focusable()
        .focused($ownsKeyboard)
        .onTapGesture {
            ownsKeyboard = true
        }
        .onKeyPress(.return) {
            guard ownsKeyboard else {
                return .ignored
            }
            model.stampActiveLyricLine(undoManager: undoManager)
            return .handled
        }
        .onKeyPress(.space) {
            guard ownsKeyboard else {
                return .ignored
            }
            model.togglePlayback()
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard ownsKeyboard else {
                return .ignored
            }
            model.moveActiveLyricLine(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard ownsKeyboard else {
                return .ignored
            }
            model.moveActiveLyricLine(by: 1)
            return .handled
        }
    }

    private var activeLine: LyricLine? {
        guard
            let draft = model.lyricDraft,
            let activeLineID = draft.activeLineID
        else {
            return nil
        }
        return draft.lines.first { $0.id == activeLineID }
    }

    private var activeLinePosition: String {
        guard
            let draft = model.lyricDraft,
            let activeLineID = draft.activeLineID,
            let index = draft.lines.firstIndex(where: {
                $0.id == activeLineID
            })
        else {
            return "—"
        }
        return "\(index + 1) of \(draft.lines.count)"
    }

    @ViewBuilder
    private var playbackClock: some View {
        if model.isPlaying {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
                playbackClockLabel(
                    presentationTime: model.playbackPresentationTime()
                )
            }
        } else {
            playbackClockLabel(
                presentationTime: model.playbackCurrentTime
            )
        }
    }

    private func playbackClockLabel(
        presentationTime: TimeInterval
    ) -> some View {
        Text(
            LyricsEditorClockPresentation.resolve(
                stateTime: model.playbackCurrentTime,
                presentationTime: presentationTime,
                isPlaying: model.isPlaying
            )
        )
        .font(.system(size: 30, weight: .medium, design: .rounded))
        .monospacedDigit()
        .frame(minWidth: 142, alignment: .leading)
    }

    private func keyboardHint(
        _ key: String,
        _ action: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(CadenceTheme.subduedFill, in: RoundedRectangle(cornerRadius: CadenceTheme.radiusControl))
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
