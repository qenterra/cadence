import SwiftUI

struct RhythmFocusView: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack
    let artworkID: UUID?
    let trackTitle: String
    let artist: String
    let layout: RhythmFocusLayout
    let artworkNamespace: Namespace.ID
    let visualQADocument: LyricDocument?
    let visualQAPresentationTime: TimeInterval?

    @State private var document: LyricDocument?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ProductionArtworkView(
                model: model,
                artworkID: artworkID,
                title: trackTitle,
                placeholder: .track,
                variant: .original,
                cornerRadius: CadenceTheme.radiusHero
            )
            .matchedGeometryEffect(
                id: RhythmFocusTransition.artworkID,
                in: artworkNamespace
            )
            .frame(
                width: layout.focusArtworkFrame.width,
                height: layout.focusArtworkFrame.height
            )
            .position(
                x: layout.focusArtworkFrame.midX,
                y: layout.focusArtworkFrame.midY
            )
            .shadow(
                color: Color.black.opacity(0.22),
                radius: 32,
                y: 18
            )

            lyricContent
                .frame(
                    width: layout.focusLyricsFrame.width,
                    height: layout.focusLyricsFrame.height
                )
                .position(
                    x: layout.focusLyricsFrame.midX,
                    y: layout.focusLyricsFrame.midY
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(track.id)-\(model.lyricsRevision)") {
            guard visualQADocument == nil else {
                return
            }
            document = await model.loadProductionLyrics(for: track)
        }
    }

    @ViewBuilder
    private var lyricContent: some View {
        if let effectiveDocument,
           effectiveDocument.timingStatus == .synchronized {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let projection = RhythmFocusLyricProjection.make(
                    document: effectiveDocument,
                    presentationTime: visualQAPresentationTime
                        ?? model.playbackPresentationTime()
                )
                RhythmFocusLyricStack(
                    document: effectiveDocument,
                    activeLineID: projection.activeLineID,
                    slotHeight: layout.focusLyricSlotHeight
                )
            }
        } else {
            unavailableLyrics
        }
    }

    private var effectiveDocument: LyricDocument? {
        visualQADocument ?? document
    }

    private var unavailableLyrics: some View {
        VStack(spacing: 7) {
            Text(trackTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Text(artist)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(unavailableLyricsCaption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableLyricsCaption: String {
        switch effectiveDocument?.timingStatus ?? .missing {
        case .missing:
            "No synchronized lyrics"
        case .unsynchronized:
            "Lyrics are not synchronized"
        case .partiallySynchronized:
            "Lyrics are only partially synchronized"
        case .synchronized:
            ""
        }
    }
}

enum RhythmFocusTransition {
    static let artworkID = "rhythm-focus-artwork"
}

extension AnyTransition {
    static var rhythmFocusLayer: AnyTransition {
        .modifier(
            active: RhythmFocusLayerModifier(
                opacity: 0,
                blurRadius: 9,
                scale: 0.985
            ),
            identity: RhythmFocusLayerModifier(
                opacity: 1,
                blurRadius: 0,
                scale: 1
            )
        )
    }
}

private struct RhythmFocusLayerModifier: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blurRadius)
            .scaleEffect(scale)
    }
}

private struct RhythmFocusLyricStack: View {
    let document: LyricDocument
    let activeLineID: LyricLine.ID?
    let slotHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: slotHeight * 2)
                    ForEach(contentLines) { line in
                        let isActive = line.id == activeLineID
                        ProductionLyricLineLabel(
                            text: line.text,
                            isActive: isActive,
                            animationDuration: ProductionLyricTiming
                                .animationDuration(
                                    for: line.id,
                                    in: document
                                ),
                            isSynchronized: true,
                            alignment: .center,
                            lineLimit: 2
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: slotHeight)
                        .id(line.id)
                        .animation(
                            reduceMotion
                                ? nil
                                : .smooth(duration: CadenceTheme.motionSpatialLong),
                            value: isActive
                        )
                    }
                    Color.clear.frame(height: slotHeight * 2)
                }
            }
            .scrollIndicators(.hidden)
            .allowsHitTesting(false)
            .onChange(of: scrollTargetID, initial: true) { _, lineID in
                guard let lineID else {
                    return
                }
                if reduceMotion {
                    proxy.scrollTo(lineID, anchor: .center)
                } else {
                    withAnimation(
                        .smooth(duration: CadenceTheme.motionSpatialLong)
                    ) {
                        proxy.scrollTo(lineID, anchor: .center)
                    }
                }
            }
        }
    }

    private var contentLines: [LyricLine] {
        document.lines.filter { !$0.isBlank }
    }

    private var scrollTargetID: LyricLine.ID? {
        activeLineID ?? contentLines.first?.id
    }
}
