import SwiftUI

struct SynchronizedLyricsView: View {
    @Bindable var model: CadenceAppModel

    let track: TrackPreview
    let document: LyricDocument

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var followsPlayback = true

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                            lyricLine(line, at: index)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 90)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onScrollPhaseChange { _, newPhase in
                    if newPhase == .interacting {
                        followsPlayback = false
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in
                            followsPlayback = false
                        }
                )

                if !followsPlayback {
                    Button {
                        followsPlayback = true
                        scrollToActiveLine(using: proxy)
                    } label: {
                        Label(
                            "Return to Current Line",
                            systemImage: "location.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .padding(22)
                }
            }
            .onAppear {
                scrollToActiveLine(using: proxy)
            }
            .onChange(of: activeLine?.id) {
                guard followsPlayback else {
                    return
                }
                scrollToActiveLine(using: proxy)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Edit Lyrics", systemImage: "pencil") {
                model.presentLyricsEditor()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 20)
            .padding(.trailing, 28)
        }
    }

    @ViewBuilder
    private func lyricLine(
        _ line: LyricLine,
        at index: Int
    ) -> some View {
        if line.isBlank {
            Color.clear
                .frame(height: 12)
                .accessibilityHidden(true)
        } else {
            let isActive = line.id == activeLine?.id

            Button {
                guard let startTime = line.startTime else {
                    return
                }
                model.progress = min(max(startTime / track.duration, 0), 1)
                followsPlayback = true
            } label: {
                HStack(alignment: .top, spacing: 0) {
                    Text(line.text)
                        .font(
                            .system(
                                size: 24,
                                weight: isActive ? .semibold : .medium
                            )
                        )
                        .foregroundStyle(
                            isActive
                                ? AnyShapeStyle(Color.primary)
                                : AnyShapeStyle(
                                    lineColor(for: index)
                                )
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(line.text)
            .accessibilityValue(accessibilityValue(for: line))
            .accessibilityHint(
                line.startTime == nil
                    ? ""
                    : "Seek playback to this lyric"
            )
        }
    }

    private var activeLine: LyricLine? {
        document.activeLine(at: track.duration * model.progress)
    }

    private var activeLineIndex: Int? {
        guard let activeLine else {
            return nil
        }
        return document.lines.firstIndex { $0.id == activeLine.id }
    }

    private func lineColor(for index: Int) -> Color {
        guard let activeLineIndex else {
            return .secondary
        }
        return abs(index - activeLineIndex) <= 2
            ? .secondary
            : .secondary.opacity(0.64)
    }

    private func accessibilityValue(
        for line: LyricLine
    ) -> String {
        var values: [String] = []
        if line.id == activeLine?.id {
            values.append("Current lyric")
        }
        if let startTime = line.startTime {
            values.append(LyricTimestampFormatter.display(startTime))
        }
        return values.joined(separator: ", ")
    }

    private func scrollToActiveLine(
        using proxy: ScrollViewProxy
    ) {
        guard let activeLine else {
            return
        }
        if reduceMotion {
            proxy.scrollTo(activeLine.id, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(activeLine.id, anchor: .center)
            }
        }
    }
}
