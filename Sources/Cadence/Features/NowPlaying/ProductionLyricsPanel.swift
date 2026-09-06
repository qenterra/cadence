import QenTerraMediaComponents
import SwiftUI

struct ProductionLyricsPanel: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack

    @AppStorage(CadencePreferences.Keys.lyricsTextSize)
    private var lyricsTextSizeRaw = LyricsTextSize.standard.rawValue
    @State private var presentation = LyricDocumentPresentationState()
    @State private var editingLineID: LyricLine.ID?
    @State private var editingText = ""
    @FocusState private var focusedEditingLineID: LyricLine.ID?

    var body: some View {
        let acceptedPresentation = presentation.acceptedPresentation(
            expectedTrackID: track.id,
            currentTrackID: model.currentPlaybackTrack?.id,
            currentLyricsRevision: model.lyricsRevision,
            isExternal: model.isCurrentPlaybackExternal
        )
        VStack(spacing: 0) {
            HStack {
                Text(
                    acceptedPresentation?.document?.timingStatus.title
                        ?? "Lyrics"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)

                Spacer()

                if !model.isCurrentPlaybackExternal {
                    Button("Edit Lyrics", systemImage: "pencil") {
                        model.presentLyricsEditor()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .frame(height: 52)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            Group {
                if model.isCurrentPlaybackExternal {
                    ContentUnavailableView {
                        Label("External File", systemImage: "play.rectangle")
                    } description: {
                        Text("Lyrics editing is available after you add the track to your library.")
                    } actions: {
                        Button("Add to Library…") {
                            model.addCurrentExternalAudioToLibrary()
                        }
                    }
                } else if let accepted = acceptedPresentation,
                          let document = accepted.document {
                    lyrics(
                        document,
                        activeLineID: presentation.activeLineID
                    )
                    .overlay {
                        if document.timingStatus == .synchronized {
                            PlaybackLyricActiveLineObserver(
                                model: model,
                                trackID: track.id,
                                document: document,
                                acceptedDocumentGeneration: accepted
                                    .request.generation,
                                activeLineID: Binding(
                                    get: { presentation.activeLineID },
                                    set: {
                                        presentation.updateActiveLineID(
                                            $0,
                                            fromAcceptedGeneration: accepted
                                                .request.generation
                                        )
                                    }
                                )
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
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
        .task(
            id: ProductionLyricsDocumentTaskKey(
                trackID: track.id,
                lyricsRevision: model.lyricsRevision,
                isExternal: model.isCurrentPlaybackExternal
            )
        ) {
            let request = presentation.beginLoad(
                trackID: track.id,
                lyricsRevision: model.lyricsRevision
            )
            cancelLineEdit()
            guard !model.isCurrentPlaybackExternal else {
                return
            }
            let loadedDocument = await model.loadProductionLyrics(for: track)
            presentation.acceptLoad(
                loadedDocument,
                for: request,
                currentTrackID: model.currentPlaybackTrack?.id,
                currentLyricsRevision: model.lyricsRevision,
                isCancelled: Task.isCancelled,
                presentationTime: model.playbackPresentationTime()
            )
        }
    }

    private func lyrics(
        _ document: LyricDocument,
        activeLineID: LyricLine.ID?
    ) -> some View {
        let lines = CadencePlayerAdapters.lyricLines(
            document.lines,
            activeLineID: activeLineID
        )
        return LyricsViewport(
            lines: lines,
            currentIdentity: activeLineID,
            resetIdentity: track.id,
            alignment: .leading
        ) { linePresentation in
            if let line = document.lines.first(where: { $0.id == linePresentation.id }) {
                lyricLine(line, presentation: linePresentation)
            }
        }
    }

    @ViewBuilder
    private func lyricLine(
        _ line: LyricLine,
        presentation: LyricLinePresentation<LyricLine.ID>
    ) -> some View {
        if editingLineID == line.id {
            TextField("Lyric Line", text: $editingText, axis: .vertical)
                .font(.system(size: lyricsTextSize.pointSize, weight: .semibold))
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .focused($focusedEditingLineID, equals: line.id)
                .onSubmit {
                    commitLineEdit(lineID: line.id)
                }
                .onExitCommand(perform: cancelLineEdit)
        } else {
            QenTerraMediaComponents.LyricLine(
                presentation: presentation,
                textSize: lyricsTextSize.pointSize,
                alignment: .leading,
                select: {
                    if let startTime = line.startTime {
                        model.seekProductionPlayback(to: startTime)
                    }
                },
                edit: {
                    beginLineEdit(line)
                }
            )
        }
    }

    private func beginLineEdit(_ line: LyricLine) {
        guard let generation = presentation.acceptedGeneration else {
            return
        }
        editingLineID = line.id
        editingText = line.text
        Task { @MainActor in
            guard presentation.acceptedGeneration == generation,
                  editingLineID == line.id else {
                return
            }
            focusedEditingLineID = line.id
        }
    }

    private func commitLineEdit(lineID: LyricLine.ID) {
        guard let document = presentation.document,
              let edit = presentation.editRequest(lineID: lineID) else {
            return
        }
        let text = editingText
        Task { @MainActor in
            guard let updated = await model.updateProductionLyricLine(
                in: document,
                lineID: lineID,
                text: text
            ) else {
                return
            }
            guard presentation.publishEditedDocument(
                updated,
                for: edit,
                currentTrackID: model.currentPlaybackTrack?.id,
                currentLyricsRevision: model.lyricsRevision,
                isCancelled: Task.isCancelled
            ) else {
                return
            }
            cancelLineEdit()
        }
    }

    private func cancelLineEdit() {
        editingLineID = nil
        focusedEditingLineID = nil
        editingText = ""
    }

    private var lyricsTextSize: LyricsTextSize {
        LyricsTextSize(rawValue: lyricsTextSizeRaw) ?? .standard
    }
}

@MainActor
struct PlaybackLyricActiveLineObserver: View {
    @Bindable var model: CadenceAppModel
    let trackID: PlaybackTrack.ID
    let document: LyricDocument
    let acceptedDocumentGeneration: UInt64?
    @Binding var activeLineID: LyricLine.ID?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let key = PlaybackLyricObservationKey(
            expectedTrackID: trackID,
            currentTrackID: model.currentPlaybackTrack?.id,
            playbackAnchor: model.playbackCurrentTime,
            isAdvancing: model.currentPlaybackTrack?.id == trackID
                && model.isPlaying
                && scenePhase == .active,
            acceptedDocumentGeneration: acceptedDocumentGeneration
        )
        Color.clear
            .task(id: key) {
                let timeline = SynchronizedLyricTimeline(document: document)
                var emissionState = LyricLineEmissionState(
                    activeLineID: activeLineID
                )

                while !Task.isCancelled {
                    let step = LyricObservationPolicy.step(
                        timeline: timeline,
                        presentationTime: model.playbackPresentationTime(),
                        isAdvancing: key.isAdvancing
                    )

                    if emissionState.update(to: step.activeLineID) {
                        activeLineID = step.activeLineID
                    }

                    guard let delay = step.nextUpdateAfter else {
                        return
                    }

                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }
                }
            }
    }
}

struct PlaybackLyricObservationKey: Equatable {
    let expectedTrackID: PlaybackTrack.ID
    let currentTrackID: PlaybackTrack.ID?
    let playbackAnchor: TimeInterval
    let isAdvancing: Bool
    let acceptedDocumentGeneration: UInt64?
}

private struct ProductionLyricsDocumentTaskKey: Equatable {
    let trackID: PlaybackTrack.ID
    let lyricsRevision: Int
    let isExternal: Bool
}

private extension LyricTimingStatus {
    var title: String {
        switch self {
        case .missing:
            String(localized: "No Lyrics")
        case .unsynchronized:
            String(localized: "Static Lyrics")
        case .partiallySynchronized:
            String(localized: "Partially Synchronized")
        case .synchronized:
            String(localized: "Synchronized Lyrics")
        }
    }
}

enum ProductionLyricLineAppearance {
    enum Tone: Equatable, Sendable {
        case primary
        case secondary
    }

    struct Style: Equatable, Sendable {
        let tone: Tone
        let opacity: Double
        let usesShimmer: Bool
    }

    static func resolve(
        isActive: Bool,
        isSynchronized: Bool
    ) -> Style {
        let shared = LyricLinePresentation(
            id: false,
            text: "",
            isActive: isActive,
            isSynchronized: isSynchronized
        )
        return Style(
            tone: shared.tone == .primary ? .primary : .secondary,
            opacity: shared.opacity,
            usesShimmer: false
        )
    }
}

struct ProductionLyricLineLabel: View {
    let text: String
    let isActive: Bool
    let isSynchronized: Bool
    let alignment: TextAlignment
    let lineLimit: Int?
    @AppStorage(CadencePreferences.Keys.lyricsTextSize)
    private var lyricsTextSizeRaw = LyricsTextSize.standard.rawValue

    init(
        text: String,
        isActive: Bool,
        isSynchronized: Bool,
        alignment: TextAlignment = .leading,
        lineLimit: Int? = nil
    ) {
        self.text = text
        self.isActive = isActive
        self.isSynchronized = isSynchronized
        self.alignment = alignment
        self.lineLimit = lineLimit
    }

    var body: some View {
        QenTerraMediaComponents.LyricLineLabel(
            presentation: LyricLinePresentation(
                id: false,
                text: text,
                isActive: isActive,
                isSynchronized: isSynchronized
            ),
            textSize: lyricsTextSize.pointSize,
            alignment: alignment,
            lineLimit: lineLimit
        )
    }

    private var lyricsTextSize: LyricsTextSize {
        LyricsTextSize(rawValue: lyricsTextSizeRaw) ?? .standard
    }
}
