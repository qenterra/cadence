import SwiftUI

struct ProductionNowPlayingView: View {
    @Bindable var model: CadenceAppModel
    let track: PlaybackTrack
    @Bindable var cadenceModeSession: CadenceModeSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rhythmPulseVisualQAState)
    private var rhythmPulseVisualQAState
    @State var tagStates: [ProductionTrackTagState] = []
    @State var newTagPath = ""
    @State var tagError: String?
    @State var isAddingTag = false
    @State private var renamedTrackTitle: String?
    @State private var isRenamePresented = false
    @State private var renameDraft = ""
    @State var isAudioDetailsPresented = false
    @State private var cadenceModeLyricDocument: LyricDocument?
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
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        CadenceModeView(
                            model: model,
                            track: track,
                            artworkID: displayedArtworkID,
                            trackTitle: displayedTrackTitle,
                            artist: track.artist,
                            layout: cadenceModeLayout,
                            artworkNamespace: cadenceModeNamespace,
                            lyricDocument: rhythmPulseVisualQAState?
                                .cadenceModeLyricDocument
                                ?? cadenceModeLyricDocument,
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
                completePendingCadenceModePresentation()
            }
            .task(id: cadenceModeSession.activationIsPending) {
                guard cadenceModeSession.activationIsPending else {
                    return
                }
                await Task.yield()
                completeCadenceModePresentation(
                    layout: cadenceModeLayout
                )
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
            guard !model.isCurrentPlaybackExternal else {
                tagStates = []
                return
            }
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
            let asset = await model.playbackArtworkAsset(
                id: displayedArtworkID,
                variant: .thumbnail
            )
            await cadenceModeSession.pulseStore.prepare(asset: asset)
        }
        .task(id: cadenceLyricsTaskID) {
            guard rhythmPulseVisualQAState == nil else {
                cadenceModeLyricDocument = nil
                return
            }
            cadenceModeLyricDocument = nil
            let loadedDocument = await model.loadProductionLyrics(for: track)
            guard !Task.isCancelled else {
                return
            }
            cadenceModeLyricDocument = loadedDocument
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

extension ProductionNowPlayingView {
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
            trackArtwork(size: artworkSize)
            trackIdentity

            if model.isCurrentPlaybackExternal {
                externalFileNotice
            } else {
                trackTags
            }
            audioQuality
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

    private func trackArtwork(size: CGFloat) -> some View {
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
        .frame(width: size, height: size)
        .contextMenu {
            if !model.isCurrentPlaybackExternal {
                ArtworkMenuItems(
                    model: model,
                    target: .managedTrack(track.id),
                    label: "Track Artwork"
                )
            }
        }
    }

    private var trackIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            trackTitleAndAction
            trackArtist
            trackAlbumAndYear
        }
    }

    private var trackTitleAndAction: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(displayedTrackTitle)
                .font(.largeTitle.weight(.bold))
                .lineLimit(2)
                .contextMenu {
                    if !model.isCurrentPlaybackExternal {
                        Button("Rename", systemImage: "pencil") {
                            beginRename()
                        }
                    }
                }

            if model.isCurrentPlaybackExternal {
                Button(
                    "Add to Library…",
                    systemImage: "plus.rectangle.on.folder"
                ) {
                    model.addCurrentExternalAudioToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                FavoriteButton(
                    isFavorite: model.currentProductionTrackIsFavorite,
                    itemName: displayedTrackTitle
                ) { requestedValue in
                    await model.setCurrentProductionTrackFavorite(requestedValue)
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var trackArtist: some View {
        if model.isCurrentPlaybackExternal {
            Text(track.artist)
                .font(.title3.weight(.medium))
        } else {
            MediaMetadataLink(
                track.artist,
                accessibilityLabel: "Open artist \(track.artist)"
            ) {
                guard let artistID = track.artistID else {
                    return
                }
                model.requestOpenProductionArtistContextually(id: artistID)
            }
            .font(.title3.weight(.medium))
        }
    }

    private var trackAlbumAndYear: some View {
        HStack(spacing: 8) {
            if model.isCurrentPlaybackExternal {
                Text(track.album)
                    .font(.body)
            } else {
                MediaMetadataLink(
                    track.album,
                    accessibilityLabel: "Open album \(track.album)"
                ) {
                    guard let albumID = track.albumID else {
                        return
                    }
                    model.requestOpenProductionAlbumContextually(id: albumID)
                }
                .font(.body)
            }

            if let year = track.year {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(year.formatted(.number.grouping(.never)))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var displayedArtworkID: UUID? {
        if model.isCurrentPlaybackExternal {
            return track.artworkID
        }
        return model.librarySession.store.tracks.first {
            $0.id == track.id
        }?.artworkID ?? track.artworkID
    }

    var displayedTrackTitle: String {
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

    private func completeCadenceModePresentation(
        layout: CadenceModeLayout
    ) {
        cadenceModeSession.updateLayout(layout)
        completePendingCadenceModePresentation()
    }

    private func completePendingCadenceModePresentation() {
        guard cadenceModeSession.activationIsPending else {
            return
        }
        // The view task runs only after Now Playing has joined the render tree,
        // so the standard scene is ready to transition.
        cadenceModeSession.setPresentationAvailable(true)
    }

    private var cadenceLyricsTaskID: String {
        let base = "\(track.id)-\(model.lyricsRevision)"
        guard let rhythmPulseVisualQAState else {
            return base
        }
        return base + "-qa-\(rhythmPulseVisualQAState.seed)"
    }

    private func beginRename() {
        renameDraft = displayedTrackTitle
        isRenamePresented = true
    }
}
