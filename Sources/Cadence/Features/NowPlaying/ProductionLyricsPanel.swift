import SwiftUI

struct ProductionLyricsPanel: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var document: LyricDocument?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document?.timingStatus.title ?? "Lyrics")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Edit Lyrics", systemImage: "pencil") {
                    model.presentLyricsEditor()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .frame(height: 52)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            Group {
                if let document {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        lyrics(
                            document,
                            presentationTime: model.playbackPresentationTime()
                        )
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Lyrics", systemImage: "quote.bubble")
                    } description: {
                        Text("No managed line-level LRC file is available.")
                    } actions: {
                        Button("Add Lyrics") {
                            model.presentLyricsEditor()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "\(track.id)-\(model.lyricsRevision)") {
            document = await model.loadProductionLyrics(for: track)
        }
    }

    private func lyrics(
        _ document: LyricDocument,
        presentationTime: TimeInterval
    ) -> some View {
        let currentLineID = activeLineID(
            in: document,
            presentationTime: presentationTime
        )

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
            HStack(alignment: .top, spacing: 0) {
                ProductionLyricLineLabel(
                    text: line.text,
                    isActive: isActive
                )
                Spacer(minLength: 0)
            }
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
        in document: LyricDocument,
        presentationTime: TimeInterval
    ) -> LyricLine? {
        document.activeLine(at: presentationTime)
    }

    private func activeLineID(
        in document: LyricDocument,
        presentationTime: TimeInterval
    ) -> LyricLine.ID? {
        activeLine(
            in: document,
            presentationTime: presentationTime
        )?.id
    }
}

private extension LyricTimingStatus {
    var title: String {
        switch self {
        case .missing:
            "No Lyrics"
        case .unsynchronized:
            "Static Lyrics"
        case .partiallySynchronized:
            "Partially Synchronized"
        case .synchronized:
            "Synchronized Lyrics"
        }
    }
}

private struct ProductionLyricLineLabel: View {
    let text: String
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase = -1.0

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foregroundStyle)
            .opacity(isActive ? 1 : 0.58)
            .shadow(
                color: isActive
                    ? Color.primary.opacity(0.28)
                    : .clear,
                radius: isActive ? 12 : 0
            )
            .onAppear {
                updateShimmer(isActive)
            }
            .onChange(of: isActive) { _, active in
                updateShimmer(active)
            }
    }

    private var foregroundStyle: LinearGradient {
        guard isActive, !reduceMotion else {
            return LinearGradient(
                colors: [
                    isActive ? Color.primary : Color.secondary,
                    isActive ? Color.primary : Color.secondary,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [
                Color.primary.opacity(0.92),
                Color.white,
                Color.primary.opacity(0.92),
            ],
            startPoint: UnitPoint(x: shimmerPhase - 0.55, y: 0.5),
            endPoint: UnitPoint(x: shimmerPhase + 0.55, y: 0.5)
        )
    }

    private func updateShimmer(_ active: Bool) {
        shimmerPhase = -0.25
        guard active, !reduceMotion else {
            return
        }
        withAnimation(
            .linear(duration: 2.8)
                .repeatForever(autoreverses: false)
        ) {
            shimmerPhase = 1.25
        }
    }
}
