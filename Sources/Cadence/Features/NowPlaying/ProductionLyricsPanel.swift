import SwiftUI

struct ProductionLyricsPanel: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var document: LyricDocument?
    @State private var editingLineID: LyricLine.ID?
    @State private var editingText = ""
    @State private var activeLineID: LyricLine.ID?
    @FocusState private var focusedEditingLineID: LyricLine.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document?.timingStatus.title ?? "Lyrics")
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
                } else if let document {
                    lyrics(document, activeLineID: activeLineID)
                        .overlay {
                            if document.timingStatus == .synchronized {
                                PlaybackLyricActiveLineObserver(
                                    model: model,
                                    document: document
                                ) { lineID in
                                    activeLineID = lineID
                                }
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
        .task(id: "\(track.id)-\(model.lyricsRevision)") {
            guard !model.isCurrentPlaybackExternal else {
                document = nil
                return
            }
            document = await model.loadProductionLyrics(for: track)
            activeLineID = document.flatMap {
                SynchronizedLyricTimeline(document: $0).activeLineID(
                    at: model.playbackPresentationTime()
                )
            }
            editingLineID = nil
            focusedEditingLineID = nil
        }
    }

    private func lyrics(
        _ document: LyricDocument,
        activeLineID: LyricLine.ID?
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(document.lines) { line in
                        if line.isBlank {
                            Color.clear.frame(height: 10)
                        } else {
                            lyricLine(
                                line,
                                isActive: activeLineID == line.id
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
                of: activeLineID,
                initial: true
            ) { _, lineID in
                guard let lineID else {
                    return
                }
                if reduceMotion {
                    proxy.scrollTo(lineID, anchor: .center)
                } else {
                    withAnimation(.smooth(duration: CadenceTheme.motionPresent)) {
                        proxy.scrollTo(lineID, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lyricLine(
        _ line: LyricLine,
        isActive: Bool
    ) -> some View {
        if editingLineID == line.id {
            TextField("Lyric Line", text: $editingText, axis: .vertical)
                .font(.system(size: 24, weight: .semibold))
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .focused($focusedEditingLineID, equals: line.id)
                .onSubmit {
                    commitLineEdit(lineID: line.id)
                }
                .onExitCommand(perform: cancelLineEdit)
        } else {
            Button {
                if let startTime = line.startTime {
                    model.seekProductionPlayback(to: startTime)
                }
            } label: {
                HStack(alignment: .top, spacing: 0) {
                    ProductionLyricLineLabel(
                        text: line.text,
                        isActive: isActive,
                        isSynchronized: line.startTime != nil
                    )
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(
                reduceMotion ? nil : .smooth(duration: CadenceTheme.motionPresent),
                value: isActive
            )
            .contextMenu {
                Button("Edit Lyric Line", systemImage: "pencil") {
                    beginLineEdit(line)
                }
            }
        }
    }

    private func beginLineEdit(_ line: LyricLine) {
        editingLineID = line.id
        editingText = line.text
        Task { @MainActor in
            focusedEditingLineID = line.id
        }
    }

    private func commitLineEdit(lineID: LyricLine.ID) {
        guard let document else {
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
            self.document = updated
            cancelLineEdit()
        }
    }

    private func cancelLineEdit() {
        editingLineID = nil
        focusedEditingLineID = nil
        editingText = ""
    }
}

struct PlaybackLyricActiveLineObserver: View {
    @Bindable var model: CadenceAppModel
    let document: LyricDocument
    let update: (LyricLine.ID?) -> Void

    var body: some View {
        let timeline = SynchronizedLyricTimeline(document: document)
        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: false)) { _ in
            let lineID = timeline.activeLineID(
                at: model.playbackPresentationTime()
            )
            Color.clear
                .onChange(of: lineID, initial: true) { _, lineID in
                    update(lineID)
                }
        }
    }
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
        Style(
            tone: isActive || !isSynchronized ? .primary : .secondary,
            opacity: !isSynchronized || isActive ? 1 : 0.58,
            usesShimmer: false
        )
    }

    static func blurRadius(
        isActive: Bool,
        isSynchronized: Bool,
        isIncreasedContrast: Bool
    ) -> CGFloat {
        guard isSynchronized, !isActive, !isIncreasedContrast else {
            return 0
        }
        return 0.7
    }
}

struct ProductionLyricLineLabel: View {
    let text: String
    let isActive: Bool
    let isSynchronized: Bool
    let alignment: TextAlignment
    let lineLimit: Int?

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

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let appearance = ProductionLyricLineAppearance.resolve(
            isActive: isActive,
            isSynchronized: isSynchronized
        )
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .multilineTextAlignment(alignment)
            .lineSpacing(3)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(
                appearance.tone == .primary
                    ? Color.primary
                    : Color.secondary
            )
            .opacity(appearance.opacity)
            .blur(
                radius: ProductionLyricLineAppearance.blurRadius(
                    isActive: isActive,
                    isSynchronized: isSynchronized,
                    isIncreasedContrast: contrast == .increased
                )
            )
    }
}
