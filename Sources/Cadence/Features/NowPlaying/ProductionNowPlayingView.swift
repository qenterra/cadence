import SwiftUI

struct ProductionNowPlayingView: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack
    @Bindable var cadenceModeSession: CadenceModeSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rhythmPulseVisualQAState)
    private var rhythmPulseVisualQAState
    @State private var tagStates: [ProductionTrackTagState] = []
    @State private var newTagPath = ""
    @State private var tagError: String?
    @State private var isAddingTag = false
    @State private var renamedTrackTitle: String?
    @State private var isRenamePresented = false
    @State private var renameDraft = ""
    @Namespace private var cadenceModeNamespace

    var body: some View {
        GeometryReader { geometry in
            let layout = NowPlayingLayoutMetrics(
                totalWidth: geometry.size.width
            )
            let cadenceModeLayout = CadenceModeLayout(
                canvasSize: geometry.size,
                contextWidth: layout.contextWidth
            )
            let isCadenceModeActive = rhythmPulseVisualQAState?.isCadenceModeActive
                ?? cadenceModeSession.isActive

            ZStack {
                if isCadenceModeActive {
                    ZStack {
                        CadenceModeBackground(
                            palette: cadenceModeSession.pulseStore.palette
                                ?? .cadenceFallback
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        RhythmPulseCanvas(
                            store: cadenceModeSession.pulseStore,
                            panelStartX: layout.contextWidth + 1
                        )

                        CadenceModeView(
                            model: model,
                            track: track,
                            artworkID: displayedArtworkID,
                            trackTitle: displayedTrackTitle,
                            artist: track.artist,
                            layout: cadenceModeLayout,
                            artworkNamespace: cadenceModeNamespace,
                            visualQADocument: rhythmPulseVisualQAState?
                                .cadenceModeLyricDocument,
                            visualQAPresentationTime: rhythmPulseVisualQAState?
                                .cadenceModePresentationTime
                        )
                    }
                    .environment(\.colorScheme, .dark)
                    .transition(reduceMotion ? .opacity : .cadenceModeLayer)
                } else {
                    standardNowPlaying(
                        layout: layout,
                        cadenceModeLayout: cadenceModeLayout
                    )
                    .transition(reduceMotion ? .opacity : .cadenceModeLayer)
                }
            }
            .task(id: cadenceModeLayout) {
                cadenceModeSession.updateLayout(cadenceModeLayout)
            }
            .clipped()
            .animation(
                reduceMotion
                    ? nil
                    : .smooth(
                        duration: CadenceTheme.motionCadenceModeEnter
                    ),
                value: isCadenceModeActive
            )
        }
        .background(CadenceTheme.contentBackground)
        .task(id: "\(track.id)-\(model.librarySession.store.tagRevision)") {
            tagStates = await (
                try? model.librarySession.store.tagStates(
                    trackID: track.id
                )
            ) ?? []
        }
        .task(id: rhythmArtworkTaskID) {
            if let rhythmPulseVisualQAState {
                cadenceModeSession.pulseStore.prepare(
                    visualQAState: rhythmPulseVisualQAState
                )
                return
            }
            guard let displayedArtworkID else {
                await cadenceModeSession.pulseStore.prepare(asset: nil)
                return
            }
            let asset = await model.librarySession.store.artworkAsset(
                id: displayedArtworkID,
                location: model.librarySession.location,
                variant: .thumbnail
            )
            await cadenceModeSession.pulseStore.prepare(asset: asset)
        }
        .catalogRenameAlert(
            "Rename Track",
            prompt: "Track Name",
            isPresented: $isRenamePresented,
            draft: $renameDraft
        ) { title in
            Task {
                if let renamed = await model.renameProductionTrack(
                    id: track.id,
                    title: title
                ) {
                    renamedTrackTitle = renamed.title
                }
            }
        }
    }
}

private extension ProductionNowPlayingView {
    private func standardNowPlaying(
        layout: NowPlayingLayoutMetrics,
        cadenceModeLayout: CadenceModeLayout
    ) -> some View {
        HStack(spacing: 0) {
            trackContext(
                artworkSize: cadenceModeLayout.standardArtworkFrame.width
            )
            .frame(width: layout.contextWidth)

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(width: 1)

            panel
                .frame(width: layout.panelWidth)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func trackContext(artworkSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ProductionArtworkView(
                model: model,
                artworkID: displayedArtworkID,
                title: displayedTrackTitle,
                placeholder: .track,
                variant: .original,
                cornerRadius: CadenceTheme.radiusHero
            )
            .matchedGeometryEffect(
                id: CadenceModeTransition.artworkID,
                in: cadenceModeNamespace
            )
            .frame(width: artworkSize, height: artworkSize)
            .contextMenu {
                ArtworkMenuItems(
                    model: model,
                    target: .managedTrack(track.id),
                    label: "Track Artwork"
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 10) {
                    Text(displayedTrackTitle)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                beginRename()
                            }
                        }

                    FavoriteButton(
                        isFavorite: model.currentProductionTrackIsFavorite,
                        itemName: displayedTrackTitle
                    ) { requestedValue in
                        await model.setCurrentProductionTrackFavorite(
                            requestedValue
                        )
                    }
                    .padding(.top, 2)
                }
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
            Spacer(minLength: 8)
            CadenceModeHint()
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
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .frame(height: 24)

                    CadenceFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(tagStates.prefix(3)) { state in
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
                            .help("Show tracks tagged " + state.tag.displayPath)
                        }

                        if tagStates.count > 3 {
                            Text("+\(tagStates.count - 3)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(height: 24)
                        }

                        TextField("Add a tag", text: $newTagPath)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .frame(width: 110, height: 24)
                            .onSubmit(addTag)
                            .disabled(isAddingTag)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                .padding(.vertical, 6)
                .frame(minHeight: 36)
                .background(
                    CadenceTheme.subduedFill,
                    in: RoundedRectangle(
                        cornerRadius: CadenceTheme.radiusControl,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CadenceTheme.radiusControl,
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
                                cornerRadius: CadenceTheme.radiusControl,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .help("Edit Tags")
                .accessibilityLabel("Edit Tags for \(displayedTrackTitle)")
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

    private var displayedTrackTitle: String {
        renamedTrackTitle ?? track.title
    }

    private var rhythmArtworkTaskID: String {
        let artworkKey = "\(displayedArtworkID?.uuidString ?? "none")"
            + "-\(model.artworkRevision)"
        guard let rhythmPulseVisualQAState else {
            return artworkKey
        }
        return artworkKey + "-qa-\(rhythmPulseVisualQAState.seed)"
    }

    private func beginRename() {
        renameDraft = displayedTrackTitle
        isRenamePresented = true
    }

    @ViewBuilder
    private var playbackFailure: some View {
        if let failure = model.playbackCoordinator?.state.failure {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    failure.message,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Retry") {
                        model.retryPlaybackFailure()
                    }
                    Button("Skip") {
                        model.skipPlaybackFailure()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .accessibilityElement(children: .contain)
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
                Button("Back", systemImage: "chevron.backward") {
                    model.dismissNowPlaying()
                }
                .labelStyle(.titleAndIcon)
                .keyboardShortcut("[", modifiers: .command)

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
