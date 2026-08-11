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
                    ForEach(
                        Array(document.lines.enumerated()),
                        id: \.element.id
                    ) { index, line in
                        if line.isBlank {
                            Color.clear.frame(height: 10)
                        } else {
                            lyricLine(
                                line,
                                isActive: currentLineID == line.id,
                                animationDuration: lineDuration(
                                    at: index,
                                    in: document
                                )
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
        isActive: Bool,
        animationDuration: TimeInterval
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
                        animationDuration: animationDuration,
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

    private func lineDuration(
        at index: Int,
        in document: LyricDocument
    ) -> TimeInterval {
        let nextStartTime = document.lines.dropFirst(index + 1)
            .lazy
            .compactMap(\.startTime)
            .first
        return ProductionLyricMotion.duration(
            startTime: document.lines[index].startTime,
            nextStartTime: nextStartTime,
            trackDuration: track.duration
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

enum ProductionLyricMotion {
    static func duration(
        startTime: TimeInterval?,
        nextStartTime: TimeInterval?,
        trackDuration: TimeInterval
    ) -> TimeInterval {
        guard let startTime else {
            return 0
        }
        let endTime: TimeInterval = if let nextStartTime, nextStartTime > startTime {
            nextStartTime
        } else if trackDuration > startTime {
            trackDuration
        } else {
            startTime + 4
        }
        return max(endTime - startTime, 1.2)
    }
}

enum ProductionLyricTiming {
    static func animationDuration(
        for lineID: LyricLine.ID,
        in document: LyricDocument
    ) -> TimeInterval {
        guard
            let index = document.lines.firstIndex(where: { $0.id == lineID }),
            let startTime = document.lines[index].startTime
        else {
            return 0
        }
        let nextStartTime = document.lines.dropFirst(index + 1)
            .lazy
            .compactMap(\.startTime)
            .first
        return max((nextStartTime ?? startTime + 4) - startTime, 1.2)
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
    let animationDuration: TimeInterval
    let isSynchronized: Bool
    let alignment: TextAlignment
    let lineLimit: Int?

    init(
        text: String,
        isActive: Bool,
        animationDuration: TimeInterval,
        isSynchronized: Bool,
        alignment: TextAlignment = .leading,
        lineLimit: Int? = nil
    ) {
        self.text = text
        self.isActive = isActive
        self.animationDuration = animationDuration
        self.isSynchronized = isSynchronized
        self.alignment = alignment
        self.lineLimit = lineLimit
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerPhase = -1.0

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .multilineTextAlignment(alignment)
            .lineSpacing(3)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foregroundStyle)
            .opacity(!isSynchronized || isActive ? 1 : 0.58)
            .blur(
                radius: ProductionLyricLineAppearance.blurRadius(
                    isActive: isActive,
                    isSynchronized: isSynchronized,
                    isIncreasedContrast: contrast == .increased
                )
            )
            .shadow(
                color: isActive && isSynchronized
                    ? CadenceTheme.informativeAccent.opacity(
                        colorScheme == .dark ? 0.30 : 0.14
                    )
                    : .clear,
                radius: isActive && isSynchronized
                    ? (colorScheme == .dark ? 10 : 6)
                    : 0
            )
            .onAppear {
                updateShimmer(isActive)
            }
            .onChange(of: isActive) { _, active in
                updateShimmer(active)
            }
    }

    private var foregroundStyle: LinearGradient {
        guard isSynchronized else {
            return LinearGradient(
                colors: [Color.primary, Color.primary],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        guard isActive, isSynchronized, !reduceMotion else {
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
                Color.primary.opacity(0.82),
                CadenceTheme.informativeAccent,
                Color.primary.opacity(0.82),
            ],
            startPoint: UnitPoint(x: shimmerPhase - 0.55, y: 0.5),
            endPoint: UnitPoint(x: shimmerPhase + 0.55, y: 0.5)
        )
    }

    private func updateShimmer(_ active: Bool) {
        shimmerPhase = -0.25
        guard
            active,
            isSynchronized,
            !reduceMotion,
            animationDuration > 0
        else {
            return
        }
        withAnimation(.linear(duration: animationDuration)) {
            shimmerPhase = 1.25
        }
    }
}
