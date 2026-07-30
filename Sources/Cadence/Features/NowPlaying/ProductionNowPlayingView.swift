import SwiftUI

struct ProductionNowPlayingView: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tagStates: [ProductionTrackTagState] = []
    @State private var newTagPath = ""
    @State private var tagError: String?
    @State private var isAddingTag = false

    var body: some View {
        GeometryReader { geometry in
            let layout = NowPlayingLayoutMetrics(
                totalWidth: geometry.size.width
            )

            HStack(spacing: 0) {
                trackContext
                    .frame(width: layout.contextWidth)

                Rectangle()
                    .fill(CadenceTheme.separator)
                    .frame(width: 1)

                panel
                    .frame(width: layout.panelWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(CadenceTheme.contentBackground)
        .id(track.id)
        .transition(.opacity)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.24),
            value: track.id
        )
        .task(id: "\(track.id)-\(model.librarySession.store.tagRevision)") {
            tagStates = await (
                try? model.librarySession.store.tagStates(
                    trackID: track.id
                )
            ) ?? []
        }
    }
}

private extension ProductionNowPlayingView {
    private var trackContext: some View {
        VStack(alignment: .leading, spacing: 22) {
            ProductionArtworkView(
                model: model,
                artworkID: displayedArtworkID,
                title: track.title,
                placeholder: .track,
                cornerRadius: 18
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 420)
            .contextMenu {
                ArtworkMenuItems(
                    model: model,
                    target: .managedTrack(track.id),
                    label: "Track Artwork"
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(track.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
                MediaMetadataLink(
                    track.artist,
                    accessibilityLabel: "Open artist \(track.artist)"
                ) {
                    guard let artistID = track.artistID else {
                        return
                    }
                    model.requestOpenProductionArtistContextually(
                        id: artistID
                    )
                }
                .font(.title3.weight(.medium))

                HStack(spacing: 8) {
                    MediaMetadataLink(
                        track.album,
                        accessibilityLabel: "Open album \(track.album)"
                    ) {
                        guard let albumID = track.albumID else {
                            return
                        }
                        model.requestOpenProductionAlbumContextually(
                            id: albumID
                        )
                    }
                    .font(.body)

                    if let year = track.year {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(
                            year.formatted(
                                .number.grouping(.never)
                            )
                        )
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            trackTags
            audioPath
            playbackFailure
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topLeading) {
            ProductionArtworkHaze(
                model: model,
                artworkID: displayedArtworkID
            )
            .frame(width: 520, height: 520)
            .offset(x: -50, y: -34)
        }
        .clipped()
    }

    private var trackTags: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(tagStates) { state in
                                Button {
                                    model.requestOpenProductionTagContextually(
                                        id: state.tag.id
                                    )
                                } label: {
                                    Text(state.tag.displayPath)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .frame(height: 24)
                                        .background(
                                            CadenceTheme.subduedFill,
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(
                                    "Show tracks tagged "
                                        + state.tag.displayPath
                                )
                            }

                            TextField("Add a tag", text: $newTagPath)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .frame(minWidth: 86, maxWidth: 130)
                                .onSubmit(addTag)
                                .disabled(isAddingTag)
                        }
                    }
                    .scrollIndicators(.hidden)

                    if !trimmedTagPath.isEmpty {
                        Button(action: addTag) {
                            Image(systemName: "plus")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(isAddingTag)
                        .help("Assign Tag")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(
                    CadenceTheme.subduedFill,
                    in: RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
                }

                Button {
                    model.openProductionTagEditor(trackID: track.id)
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 34, height: 34)
                        .background(
                            CadenceTheme.subduedFill,
                            in: RoundedRectangle(
                                cornerRadius: 9,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .help("Edit Tags")
                .accessibilityLabel("Edit Tags for \(track.title)")
            }

            if let tagError {
                Text(tagError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trimmedTagPath: String {
        newTagPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTag() {
        let path = trimmedTagPath
        guard !path.isEmpty else {
            return
        }
        Task { @MainActor in
            isAddingTag = true
            defer { isAddingTag = false }
            do {
                _ = try await model.librarySession.store.createTagAndAssign(
                    displayPath: path,
                    trackID: track.id
                )
                newTagPath = ""
                tagError = nil
                tagStates = try await model.librarySession.store.tagStates(
                    trackID: track.id
                )
            } catch {
                tagError = error.localizedDescription
            }
        }
    }

    private var displayedArtworkID: UUID? {
        model.librarySession.store.tracks.first {
            $0.id == track.id
        }?.artworkID ?? track.artworkID
    }

    @ViewBuilder
    private var playbackFailure: some View {
        if let failure = model.playbackCoordinator?.state.failure {
            Label(failure.message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Playback error: \(failure.message)")
        }
    }

    @ViewBuilder
    private var audioPath: some View {
        if let path = model.playbackCoordinator?.state.audioPath {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Path")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(
                    "\(path.codec.uppercased()) · "
                        + "\(sampleRateText(path.sourceSampleRate)) · "
                        + "\(path.sourceChannelCount) ch"
                )
                .font(.subheadline)

                Text(
                    "\(path.backend.rawValue.uppercased()) · "
                        + path.outputRoute.name
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if path.nextTransitionIsGapless {
                    Label(
                        "Next transition is gapless-capable",
                        systemImage: "arrow.left.and.right"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(sourcePresentation(path.sourceSpatialFormat))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.selectedNowPlayingPanel.title)
                    .font(.title2.weight(.semibold))
                Spacer()
                NowPlayingPanelPicker(model: model)
            }
            .padding(.horizontal, 28)
            .frame(height: 76)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            switch model.selectedNowPlayingPanel {
            case .lyrics:
                ProductionLyricsPanel(
                    model: model,
                    track: track
                )
            case .queue:
                ProductionPlaybackQueuePanel(model: model)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sampleRateText(
        _ sampleRate: Double
    ) -> String {
        let kilohertz = sampleRate / 1000
        return kilohertz.formatted(
            .number.precision(.fractionLength(0 ... 1))
        ) + " kHz"
    }

    private func sourcePresentation(
        _ format: StoredSpatialFormat
    ) -> String {
        switch format {
        case .dolbyAtmos:
            "Dolby Atmos source"
        case .multichannel:
            "Multichannel source"
        case .stereo:
            "Stereo source"
        case .unknown:
            "Source presentation unknown"
        }
    }
}
