import SwiftUI

struct ProductionLyricsPanel: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var document: LyricDocument?
    @State private var editingLineID: LyricLine.ID?
    @State private var editingText = ""
    @FocusState private var focusedEditingLineID: LyricLine.ID?

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
                    if document.timingStatus == .unsynchronized {
                        lyrics(
                            document,
                            presentationTime: 0
                        )
                    } else {
                        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                            lyrics(
                                document,
                                presentationTime: model.playbackPresentationTime()
                            )
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
            document = await model.loadProductionLyrics(for: track)
            editingLineID = nil
            focusedEditingLineID = nil
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
            ScrollView(.vertical) {
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
