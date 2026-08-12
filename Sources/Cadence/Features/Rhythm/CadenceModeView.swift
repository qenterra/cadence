import SwiftUI

struct CadenceModeView: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack
    let artworkID: UUID?
    let trackTitle: String
    let artist: String
    let layout: CadenceModeLayout
    let artworkNamespace: Namespace.ID
    let lyricDocument: LyricDocument?
    let visualQAPresentationTime: TimeInterval?

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
                id: CadenceModeTransition.artworkID,
                in: artworkNamespace
            )
            .frame(
                width: layout.modeArtworkFrame.width,
                height: layout.modeArtworkFrame.height
            )
            .position(
                x: layout.modeArtworkFrame.midX,
                y: layout.modeArtworkFrame.midY
            )
            .shadow(
                color: Color.black.opacity(0.22),
                radius: 32,
                y: 18
            )

            lyricContent
                .frame(
                    width: layout.modeLyricsFrame.width,
                    height: layout.modeLyricsFrame.height
                )
                .position(
                    x: layout.modeLyricsFrame.midX,
                    y: layout.modeLyricsFrame.midY
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var lyricContent: some View {
        if let lyricDocument,
           lyricDocument.timingStatus == .synchronized {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let projection = CadenceModeLyricProjection.make(
                    document: lyricDocument,
                    presentationTime: visualQAPresentationTime
                        ?? model.playbackPresentationTime()
                )
                CadenceModeLyricStack(
                    document: lyricDocument,
                    activeLineID: projection.activeLineID,
                    slotHeight: layout.modeLyricSlotHeight
                )
            }
        } else {
            unavailableLyrics
        }
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
        switch lyricDocument?.timingStatus ?? .missing {
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

enum CadenceModeTransition {
    static let artworkID = "cadence-mode-artwork"
}

extension AnyTransition {
    static var cadenceModeLayer: AnyTransition {
        .modifier(
            active: CadenceModeLayerModifier(
                opacity: 0,
                blurRadius: 9,
                scale: 0.985
            ),
            identity: CadenceModeLayerModifier(
                opacity: 1,
                blurRadius: 0,
                scale: 1
            )
        )
    }
}

private struct CadenceModeLayerModifier: ViewModifier {
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

private struct CadenceModeLyricStack: View {
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
