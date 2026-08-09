import SwiftUI

struct LyricsSearchResultsSection: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore

    var body: some View {
        if !store.catalogSearchResults.lyrics.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Lyrics Matches")
                        .font(.title2.bold())
                    Text(store.catalogSearchResults.lyrics.count.formatted())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                LazyVStack(spacing: 8) {
                    ForEach(store.catalogSearchResults.lyrics) { result in
                        lyricResultRow(result)
                    }
                }
            }
        } else if store.lyricsSearchIndexState == .indexing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Indexing Lyrics…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if case let .failed(message) = store.lyricsSearchIndexState {
            Label("Lyrics Search Unavailable", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(message)
        }
    }
}

private extension LyricsSearchResultsSection {
    func lyricResultRow(
        _ result: LyricsCatalogSearchResult
    ) -> some View {
        HStack(spacing: 12) {
            ProductionArtworkView(
                model: model,
                artworkID: result.track.artworkID,
                title: result.track.title,
                placeholder: .track,
                variant: .trackRow,
                cornerRadius: CadenceTheme.radiusControl
            )
            .frame(width: 40, height: 40)
            resultLabels(result)
            Spacer(minLength: 0)
            Image(systemName: "text.quote")
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(CadenceTheme.subduedFill)
        .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusGroup))
        .contentShape(Rectangle())
        .focusable()
        .onTapGesture(count: 2) {
            play(result)
        }
        .onTapGesture(count: 1) {
            model.presentLyricsSearchResult(result)
        }
        .onKeyPress(.return, phases: .down) { _ in
            play(result)
            return .handled
        }
        .contextMenu {
            Button("Open Lyrics", systemImage: "text.quote") {
                model.presentLyricsSearchResult(result)
            }
            Button("Play", systemImage: "play.fill") {
                play(result)
            }
        }
        .accessibilityLabel(
            "Lyrics match in \(result.track.title) by \(result.track.artist)"
        )
    }

    func resultLabels(
        _ result: LyricsCatalogSearchResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(result.track.title)
                    .font(.body.weight(.medium))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(result.track.artist)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            highlightedSnippet(result.match.snippet)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    func play(
        _ result: LyricsCatalogSearchResult
    ) {
        model.playProductionTrack(
            result.track,
            within: [result.track],
            source: .adHoc
        )
    }

    func highlightedSnippet(
        _ snippet: String
    ) -> Text {
        let components = snippet.components(separatedBy: "<mark>")
        guard components.count > 1 else {
            return Text(snippet.replacingOccurrences(of: "</mark>", with: ""))
        }
        var result = AttributedString(components[0])
        for component in components.dropFirst() {
            appendMarkedComponent(component, to: &result)
        }
        return Text(result)
    }

    func appendMarkedComponent(
        _ component: String,
        to result: inout AttributedString
    ) {
        let parts = component.components(separatedBy: "</mark>")
        var match = AttributedString(parts[0])
        match.inlinePresentationIntent = .stronglyEmphasized
        result.append(match)
        if parts.count > 1 {
            result.append(
                AttributedString(
                    parts.dropFirst().joined(separator: "</mark>")
                )
            )
        }
    }
}
