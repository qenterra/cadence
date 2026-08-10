import SwiftUI

struct LyricsSearchPreviewView: View {
    @Bindable var model: CadenceAppModel
    let target: LyricsCatalogSearchResult

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var document: LyricDocument?
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
            content
        }
        .background(CadenceTheme.contentBackground)
        .task(id: target.id) {
            document = try? await model.librarySession.store.lyricsDocument(
                trackID: target.track.id
            )
            loadFailed = document == nil
        }
    }
}

private extension LyricsSearchPreviewView {
    var header: some View {
        HStack(spacing: 14) {
            Button("Back to Search", systemImage: "chevron.backward") {
                model.dismissLyricsSearchResult()
            }
            .labelStyle(.iconOnly)
            .help("Back to Search")

            ProductionArtworkView(
                model: model,
                artworkID: target.track.artworkID,
                title: target.track.title,
                placeholder: .track,
                variant: .trackRow,
                cornerRadius: CadenceTheme.radiusControl
            )
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.track.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(target.track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Play from Beginning", systemImage: "play.fill") {
                model.playProductionTrack(
                    target.track,
                    within: [target.track],
                    source: .adHoc
                )
            }

            if let timestamp = target.match.timestamp {
                Button("Play from This Line", systemImage: "play.circle") {
                    model.playProductionTrack(
                        target.track,
                        within: [target.track],
                        source: .adHoc,
                        startingAt: timestamp
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
    }

    @ViewBuilder
    var content: some View {
        if let document {
            lyrics(document)
        } else if loadFailed {
            ContentUnavailableView(
                "Lyrics Unavailable",
                systemImage: "text.quote",
                description: Text("The matching lyric file could not be opened.")
            )
        } else {
            ProgressView("Loading Lyrics")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func lyrics(
        _ document: LyricDocument
    ) -> some View {
        let targetLineID = document.lines.indices.contains(target.match.lineIndex)
            ? document.lines[target.match.lineIndex].id
            : nil
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(document.lines) { line in
                        if line.isBlank {
                            Color.clear.frame(height: 8)
                        } else {
                            Text(line.text)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(
                                    line.id == targetLineID ? .primary : .secondary
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    if line.id == targetLineID {
                                        RoundedRectangle(
                                            cornerRadius: CadenceTheme.radiusControl
                                        )
                                        .fill(CadenceTheme.selectionFill)
                                    }
                                }
                                .id(line.id)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
            }
            .onAppear {
                guard let targetLineID else { return }
                Task { @MainActor in
                    await Task.yield()
                    if reduceMotion {
                        proxy.scrollTo(targetLineID, anchor: .center)
                    } else {
                        withAnimation(.smooth(duration: 0.24)) {
                            proxy.scrollTo(targetLineID, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}
