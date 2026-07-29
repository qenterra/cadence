import SwiftUI

struct ProductionLyricsPanel: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var document: LyricDocument?

    var body: some View {
        Group {
            if let document {
                lyrics(document)
            } else {
                ContentUnavailableView {
                    Label("No Lyrics", systemImage: "quote.bubble")
                } description: {
                    Text("No linked line-level LRC file is available.")
                }
            }
        }
        .task(id: track.id) {
            document = await model.loadProductionLyrics(for: track)
        }
    }

    private func lyrics(
        _ document: LyricDocument
    ) -> some View {
        let currentLineID = activeLineID(in: document)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(document.lines) { line in
                        if line.isBlank {
                            Color.clear.frame(height: 10)
                        } else {
                            lyricLine(
                                line,
                                isActive: currentLineID == line.id
                            )
                            .id(line.id)
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(
                of: currentLineID,
                initial: true
            ) { _, lineID in
                guard let lineID else {
                    return
                }
                if reduceMotion {
                    proxy.scrollTo(lineID, anchor: .center)
                } else {
                    withAnimation(.smooth(duration: 0.24)) {
                        proxy.scrollTo(lineID, anchor: .center)
                    }
                }
            }
        }
    }

    private func lyricLine(
        _ line: LyricLine,
        isActive: Bool
    ) -> some View {
        Button {
            if let startTime = line.startTime {
                model.seekProductionPlayback(to: startTime)
            }
        } label: {
            ProductionLyricLineLabel(
                text: line.text,
                isActive: isActive
            )
            .scaleEffect(
                isActive && !reduceMotion ? 1.015 : 1,
                anchor: .leading
            )
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(line.startTime == nil)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.24),
            value: isActive
        )
    }

    private func activeLine(
        in document: LyricDocument
    ) -> LyricLine? {
        document.activeLine(at: model.playbackCurrentTime)
    }

    private func activeLineID(
        in document: LyricDocument
    ) -> LyricLine.ID? {
        activeLine(in: document)?.id
    }
}

private struct ProductionLyricLineLabel: View {
    let text: String
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -220

    var body: some View {
        baseText
            .foregroundStyle(isActive ? .primary : .secondary)
            .opacity(isActive ? 1 : 0.58)
            .overlay {
                if isActive, !reduceMotion {
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.primary.opacity(0.42),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 150)
                    .offset(x: shimmerOffset)
                    .mask(baseText)
                    .allowsHitTesting(false)
                }
            }
            .shadow(
                color: isActive
                    ? Color.primary.opacity(0.16)
                    : .clear,
                radius: isActive ? 9 : 0
            )
            .onAppear {
                guard isActive, !reduceMotion else {
                    return
                }
                withAnimation(
                    .linear(duration: 2.6)
                        .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 520
                }
            }
            .onChange(of: isActive) { _, active in
                guard active, !reduceMotion else {
                    shimmerOffset = -220
                    return
                }
                shimmerOffset = -220
                withAnimation(
                    .linear(duration: 2.6)
                        .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 520
                }
            }
    }

    private var baseText: some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
    }
}
