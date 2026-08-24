import SwiftUI

extension EnvironmentValues {
    /// Deterministic screenshot-only override. A nil value leaves the system
    /// Reduce Motion setting authoritative for production behavior.
    @Entry var cadenceModeVisualQAReduceMotionOverride: Bool?

    /// Keeps records-only captures deterministic without overriding the
    /// runtime accessibility setting when no visual-QA value is installed.
    @Entry var cadenceModeVisualQABackgroundReduceMotionOverride: Bool?

    @Entry var cadenceModeVisualReadinessObserver:
        CadenceModeVisualReadinessObserver?
}

struct CadenceModeArtworkRenderSnapshot: Equatable, Sendable {
    let trackID: UUID
    let artworkScale: CGFloat
    let artworkFrame: CGRect
}

final class CadenceModeVisualReadinessObserver: Equatable, @unchecked Sendable {
    private let artworkReadyClosure: @MainActor @Sendable (UUID) -> Void
    private let renderClosure:
        @MainActor @Sendable (CadenceModeArtworkRenderSnapshot) -> Void

    init(
        artworkReady: @escaping @MainActor @Sendable (UUID) -> Void,
        render: @escaping @MainActor @Sendable (
            CadenceModeArtworkRenderSnapshot
        ) -> Void
    ) {
        artworkReadyClosure = artworkReady
        renderClosure = render
    }

    @MainActor
    func notifyArtworkReady(trackID: UUID) {
        artworkReadyClosure(trackID)
    }

    @MainActor
    func notifyRender(_ snapshot: CadenceModeArtworkRenderSnapshot) {
        renderClosure(snapshot)
    }

    static func == (
        lhs: CadenceModeVisualReadinessObserver,
        rhs: CadenceModeVisualReadinessObserver
    ) -> Bool {
        lhs === rhs
    }
}

enum CadenceModeVisualReadinessGeometryPolicy {
    static func observerToInstall(
        _ observer: CadenceModeVisualReadinessObserver?,
        countInstallation: () -> Void = {}
    ) -> CadenceModeVisualReadinessObserver? {
        guard let observer else {
            return nil
        }
        countInstallation()
        return observer
    }
}

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
    let visualQABassLevel: Float?
    @State private var activeLineID: LyricLine.ID?
    @State private var bassSmoother = CadenceModeBassSmoother()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cadenceModeVisualQAReduceMotionOverride)
    private var visualQAReduceMotionOverride
    @Environment(\.cadenceModeVisualReadinessObserver)
    private var visualReadinessObserver

    var body: some View {
        ZStack(alignment: .topLeading) {
            bassReactiveArtwork
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

    private var bassReactiveArtwork: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 120.0,
                paused: visualQABassLevel != nil
                    || effectiveReduceMotion
                    || !model.isPlaying
            )
        ) { timeline in
            let usesVisualQA = visualQABassLevel != nil
            let targetLevel = visualQABassLevel ?? model.playbackBassLevel
            let displayedLevel: Float = if usesVisualQA {
                targetLevel
            } else if effectiveReduceMotion || !model.isPlaying {
                bassSmoother.reset(trackID: track.id)
            } else {
                bassSmoother.resolve(
                    trackID: track.id,
                    target: targetLevel,
                    timestamp: timeline.date.timeIntervalSinceReferenceDate
                )
            }
            let response = CadenceModeBassResponse.resolve(
                level: displayedLevel,
                reduceMotion: effectiveReduceMotion,
                isPlaying: usesVisualQA || model.isPlaying
            )

            ProductionArtworkView(
                model: model,
                artworkID: artworkID,
                title: trackTitle,
                placeholder: .track,
                variant: .original,
                cornerRadius: CadenceTheme.radiusHero,
                onReady: {
                    visualReadinessObserver?.notifyArtworkReady(
                        trackID: track.id
                    )
                }
            )
            .scaleEffect(response.artworkScale)
            .overlay {
                if let visualReadinessObserver =
                    CadenceModeVisualReadinessGeometryPolicy
                        .observerToInstall(visualReadinessObserver) {
                    visualReadinessOverlay(
                        observer: visualReadinessObserver,
                        response: response
                    )
                }
            }
        }
    }

    private func visualReadinessOverlay(
        observer: CadenceModeVisualReadinessObserver,
        response: CadenceModeBassResponse
    ) -> some View {
        GeometryReader { geometry in
            let snapshot = CadenceModeArtworkRenderSnapshot(
                trackID: track.id,
                artworkScale: response.artworkScale,
                artworkFrame: geometry.frame(in: .global)
            )
            Color.clear
                .onAppear {
                    observer.notifyRender(snapshot)
                }
                .onChange(of: snapshot) { _, updatedSnapshot in
                    observer.notifyRender(updatedSnapshot)
                }
        }
    }

    private var effectiveReduceMotion: Bool {
        visualQAReduceMotionOverride ?? systemReduceMotion
    }

    @ViewBuilder
    private var lyricContent: some View {
        if let lyricDocument,
           lyricDocument.timingStatus == .synchronized {
            synchronizedLyrics(lyricDocument)
        } else {
            unavailableLyrics
        }
    }

    @ViewBuilder
    private func synchronizedLyrics(
        _ lyricDocument: LyricDocument
    ) -> some View {
        if let visualQAPresentationTime {
            lyricStack(
                lyricDocument,
                activeLineID: SynchronizedLyricTimeline(
                    document: lyricDocument
                ).activeLineID(at: visualQAPresentationTime)
            )
        } else {
            let projectedActiveLineID = LyricDocumentLineProjection
                .activeLineID(activeLineID, in: lyricDocument)
            lyricStack(
                lyricDocument,
                activeLineID: projectedActiveLineID
            )
            .overlay {
                PlaybackLyricActiveLineObserver(
                    model: model,
                    trackID: track.id,
                    document: lyricDocument,
                    acceptedDocumentGeneration: nil,
                    activeLineID: $activeLineID
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func lyricStack(
        _ document: LyricDocument,
        activeLineID: LyricLine.ID?
    ) -> some View {
        CadenceModeLyricStack(
            document: document,
            activeLineID: activeLineID,
            slotHeight: layout.modeLyricSlotHeight,
            seek: model.seekProductionPlayback
        )
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

struct CadenceModeBassResponse: Equatable, Sendable {
    let artworkScale: CGFloat

    static let identity = CadenceModeBassResponse(artworkScale: 1)

    static func resolve(
        level: Float,
        reduceMotion: Bool,
        isPlaying: Bool = true
    ) -> CadenceModeBassResponse {
        guard isPlaying, !reduceMotion, level.isFinite else {
            return .identity
        }
        let level = CGFloat(min(max(level, 0), 1))
        let shapedLevel = level * level
        return CadenceModeBassResponse(
            artworkScale: 1 + level * 0.025 + shapedLevel * 0.018
        )
    }
}

@MainActor
final class CadenceModeBassSmoother {
    private static let attackDuration = 0.009
    private static let releaseDuration = 0.115
    private static let fallbackFrameDuration = 1.0 / 120.0

    private var value: Float = 0
    private var previousTimestamp: TimeInterval?
    private var trackID: UUID?

    func resolve(
        trackID: UUID,
        target: Float,
        timestamp: TimeInterval
    ) -> Float {
        if self.trackID != trackID {
            reset(trackID: trackID)
        }
        let target = target.isFinite ? min(max(target, 0), 1) : 0
        let rawFrameDuration = previousTimestamp.flatMap { previous in
            timestamp.isFinite ? timestamp - previous : nil
        } ?? Self.fallbackFrameDuration
        if timestamp.isFinite {
            previousTimestamp = timestamp
        }
        let frameDuration = min(
            max(rawFrameDuration, 1.0 / 240.0),
            1.0 / 30.0
        )
        let duration = target > value
            ? Self.attackDuration
            : Self.releaseDuration
        let interpolation = Float(1 - exp(-frameDuration / duration))
        value += (target - value) * interpolation
        if abs(target - value) < 0.0001 {
            value = target
        }
        return value
    }

    @discardableResult
    func reset(trackID: UUID? = nil) -> Float {
        self.trackID = trackID
        value = 0
        previousTimestamp = nil
        return 0
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
                scale: 0.985
            ),
            identity: CadenceModeLayerModifier(
                opacity: 1,
                scale: 1
            )
        )
    }
}

private struct CadenceModeLayerModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

private struct CadenceModeLyricStack: View {
    let document: LyricDocument
    let activeLineID: LyricLine.ID?
    let slotHeight: CGFloat
    let seek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cadenceModeVisualQAReduceMotionOverride)
    private var visualQAReduceMotionOverride

    var body: some View {
        let motion = LyricMotionBehavior.resolve(
            reduceMotion: visualQAReduceMotionOverride ?? systemReduceMotion
        )
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: slotHeight * 2)
                    ForEach(contentLines) { line in
                        let isActive = line.id == activeLineID
                        Button {
                            guard let seekTime = CadenceModeLyricInteraction
                                .seekTime(for: line) else {
                                return
                            }
                            seek(seekTime)
                        } label: {
                            ProductionLyricLineLabel(
                                text: line.text,
                                isActive: isActive,
                                isSynchronized: true,
                                alignment: .center,
                                lineLimit: 2
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: slotHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                        .animation(
                            motion.animatesEmphasis
                                ? .smooth(
                                    duration: CadenceTheme.motionSpatialLong
                                )
                                : nil,
                            value: isActive
                        )
                    }
                    Color.clear.frame(height: slotHeight * 2)
                }
            }
            .scrollIndicators(.hidden)
            .mask(CadenceModeLyricsEdgeFade())
            .onChange(of: activeLineID, initial: true) { _, lineID in
                guard let lineID else {
                    return
                }
                if motion.animatesScroll {
                    withAnimation(
                        .smooth(duration: CadenceTheme.motionSpatialLong)
                    ) {
                        proxy.scrollTo(lineID, anchor: .center)
                    }
                } else {
                    proxy.scrollTo(lineID, anchor: .center)
                }
            }
        }
    }

    private var contentLines: [LyricLine] {
        document.lines.filter { !$0.isBlank }
    }
}

enum CadenceModeLyricInteraction {
    static func seekTime(for line: LyricLine) -> TimeInterval? {
        line.startTime
    }
}

struct CadenceModeLyricsEdgeFade: View {
    static let topOpaqueLocation = 0.18
    static let bottomFadeLocation = 0.88

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: Self.topOpaqueLocation),
                .init(color: .black, location: Self.bottomFadeLocation),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
