// Native renderer benchmarks and invariants share one instrumented AppKit harness.
// swiftlint:disable file_length

import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

extension AllTracksPerformanceTests {
    @Test("Track display values are immutable and preformatted")
    func trackDisplayProjectionIsPreformatted() {
        let track = LibraryTrackProjection(
            id: deterministicUUID(81000),
            title: "  Fixture Track  ",
            artistID: deterministicUUID(81001),
            artist: "  Fixture Artist  ",
            albumID: deterministicUUID(81002),
            album: "  Fixture Album  ",
            duration: 65.4,
            year: 2024,
            codec: " .flac ",
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            isFavorite: true,
            isExplicit: true,
            customArtworkID: deterministicUUID(81003),
            artworkID: deterministicUUID(81003),
            relativeMediaPath: "fixture.flac",
            lastPlayedAt: nil,
            hasSynchronizedLyrics: true
        )

        let projection = TrackRowDisplayProjection(
            track: track,
            isCurrentTrack: true,
            isPlaying: true
        )

        #expect(projection.id == track.id)
        #expect(projection.title == "Fixture Track")
        #expect(projection.artist == "Fixture Artist")
        #expect(projection.album == "Fixture Album")
        #expect(projection.year == "2024")
        #expect(projection.duration == "1:05")
        #expect(projection.isFavorite)
        #expect(projection.isExplicit)
        #expect(projection.isCurrentTrack)
        #expect(projection.isPlaying)
        #expect(projection.artworkRequest == ProductionArtworkRequest(
            artworkID: track.artworkID,
            variant: .trackRow
        ))
        #expect(
            projection.accessibilityLabel
                == "Fixture Track, Fixture Artist, Fixture Album, 1:05"
        )
    }

    @Test("Cell reuse clears hover-only controls for the new track")
    func nativeCellReuseClearsHoverState() throws {
        let first = nativeInteractionProjection(index: 1)
        let second = nativeInteractionProjection(index: 2)
        let cell = NativeTrackTableCell()

        configureInteractionCell(cell, projection: first)
        cell.updatePointerHover(isHovered: true)
        let favorite = try nativeFavoriteButton(in: cell)
        #expect(!favorite.isHidden)

        configureInteractionCell(cell, projection: second)

        #expect(cell.representedTrackID == second.id)
        #expect(favorite.isHidden)
    }

    @Test("A non-favorite heart belongs only to the actual hovered row")
    func nativeFavoriteVisibilityIsPointerOwned() {
        #expect(
            NativeFavoriteVisibility.resolve(
                isFavorite: false,
                isHovered: false,
                isLiveScrolling: false
            ) == .hidden
        )
        #expect(
            NativeFavoriteVisibility.resolve(
                isFavorite: false,
                isHovered: true,
                isLiveScrolling: false
            ) == .emptySecondary
        )
        #expect(
            NativeFavoriteVisibility.resolve(
                isFavorite: false,
                isHovered: true,
                isLiveScrolling: true
            ) == .emptySecondary
        )
        #expect(
            NativeFavoriteVisibility.resolve(
                isFavorite: true,
                isHovered: false,
                isLiveScrolling: true
            ) == .filledPrimary
        )
    }

    @Test("Selection never reveals an idle non-favorite heart")
    func nativeSelectionDoesNotRevealFavoriteControl() throws {
        let cell = NativeTrackTableCell()
        let projection = nativeInteractionProjection(index: 8)
        cell.configure(
            .track(projection),
            columns: [],
            widths: TrackTableColumnPolicy.defaultWidths,
            isSelected: true,
            isFocused: true,
            isLiveScrolling: false
        )

        #expect(try nativeFavoriteButton(in: cell).isHidden)
    }

    @Test("Track title consumes the complete remaining metadata width")
    func nativeTitleConsumesRemainingWidth() throws {
        let cell = NativeTrackTableCell(
            frame: NSRect(x: 0, y: 0, width: 620, height: 58)
        )
        configureInteractionCell(
            cell,
            projection: nativeInteractionProjection(index: 3),
            widths: TrackTableResolvedWidths(
                song: 400,
                album: 190,
                year: 64,
                time: 64
            )
        )
        cell.layout()

        let title = try nativeTextField(
            in: cell,
            value: "A deliberately long track title"
        )
        let expectedOrigin = TrackTableColumnPolicy.horizontalInset
            + TrackTableColumnPolicy.favoriteControlWidth
            + TrackTableColumnPolicy.columnSpacing
            + 40
            + TrackTableColumnPolicy.songContentSpacing
        let expectedWidth = TrackTableColumnPolicy.horizontalInset
            + 400
            - expectedOrigin

        #expect(abs(title.frame.width - expectedWidth) < 0.5)
        #expect(title.toolTip == title.stringValue)
    }

    @Test("Production rows do not render codec or synchronized lyric badges")
    func nativeRowsOmitTechnicalBadges() {
        let cell = NativeTrackTableCell(
            frame: NSRect(x: 0, y: 0, width: 900, height: 58)
        )
        configureInteractionCell(
            cell,
            projection: nativeInteractionProjection(index: 4)
        )
        cell.layout()

        let strings = cell.subviews.flatMap { view -> [String] in
            if let field = view as? NSTextField {
                return [field.stringValue]
            }
            if let button = view as? NSButton {
                return [button.title]
            }
            return []
        }

        #expect(!strings.contains("FLAC"))
        #expect(!strings.contains("LRC"))
    }

    @Test("Artist and album metadata fit before AppKit truncates them")
    func nativeMetadataLinksFitTheirRenderedText() throws {
        let cell = NativeTrackTableCell(
            frame: NSRect(x: 0, y: 0, width: 900, height: 58)
        )
        configureInteractionCell(
            cell,
            projection: nativeInteractionProjection(index: 5),
            columns: [.album],
            widths: TrackTableResolvedWidths(
                song: 520,
                album: 190,
                year: 0,
                time: 0
            )
        )
        cell.layout()

        let artist = try nativeTextField(in: cell, value: "Veilr")
        let album = try nativeTextField(
            in: cell,
            value: "Artificial Minds"
        )
        #expect(artist.frame.width >= metadataCellWidth(artist))
        #expect(album.frame.width >= metadataCellWidth(album))
        #expect(
            cell.hitTest(
                NSPoint(x: artist.frame.midX, y: artist.frame.midY)
            ) === artist
        )
        #expect(
            cell.hitTest(
                NSPoint(x: album.frame.midX, y: album.frame.midY)
            ) === album
        )
    }

    @Test("Native row chrome resolves only to Cadence semantic tones")
    func nativeChromeUsesCadenceTones() {
        let selected = NativeTrackTableChromePresentation.resolve(
            isSelected: true,
            isFocused: true,
            isHovered: false,
            isLiveScrolling: false,
            isFavorite: true
        )
        let hovered = NativeTrackTableChromePresentation.resolve(
            isSelected: false,
            isFocused: false,
            isHovered: true,
            isLiveScrolling: false,
            isFavorite: false
        )
        let hoveredWhileScrolling = NativeTrackTableChromePresentation.resolve(
            isSelected: false,
            isFocused: false,
            isHovered: true,
            isLiveScrolling: true,
            isFavorite: false
        )

        #expect(selected.fill == .selection)
        #expect(selected.outline == .clear)
        #expect(selected.favorite == .primary)
        #expect(hovered.fill == .hover)
        #expect(hovered.outline == .clear)
        #expect(hovered.favorite == .secondary)
        #expect(hoveredWhileScrolling.fill == .hover)
    }

    @Test("Single-line metadata is centered while the song stack stays centered")
    func nativeTrackRowGeometryAlignsMetadata() {
        let geometry = NativeTrackRowGeometry(rowHeight: 58)

        #expect(
            abs(
                geometry.contentBounds.midY
                    - geometry.singleLineFrame.midY
            ) < 0.5
        )
        #expect(
            abs(
                geometry.titleFrame.midY
                    - geometry.singleLineFrame.midY
            ) > 0.5
        )
        #expect(geometry.artistFrame.maxY < geometry.titleFrame.minY)
        #expect(
            abs(
                geometry.contentBounds.midY
                    - geometry.twoLineBounds.midY
            ) < 0.5
        )
    }

    @Test("Rendered single-line metadata columns are vertically centered")
    func nativeRenderedMetadataIsVerticallyCentered() throws {
        let cell = NativeTrackTableCell(
            frame: NSRect(x: 0, y: 0, width: 900, height: 58)
        )
        configureInteractionCell(
            cell,
            projection: nativeInteractionProjection(index: 9),
            columns: [.album, .year, .time]
        )
        cell.layout()

        let album = try nativeTextField(
            in: cell,
            value: "Artificial Minds"
        )
        let year = try nativeTextField(in: cell, value: "2025")
        let duration = try nativeTextField(in: cell, value: "3:15")

        #expect(abs(cell.bounds.midY - album.frame.midY) < 0.5)
        #expect(abs(cell.bounds.midY - year.frame.midY) < 0.5)
        #expect(abs(cell.bounds.midY - duration.frame.midY) < 0.5)
    }

    private func configureInteractionCell(
        _ cell: NativeTrackTableCell,
        projection: TrackRowDisplayProjection,
        columns: [TrackTableColumn] = [],
        widths: TrackTableResolvedWidths = TrackTableColumnPolicy.defaultWidths
    ) {
        cell.configure(
            .track(projection),
            columns: columns,
            widths: widths,
            isSelected: false,
            isFocused: false,
            isLiveScrolling: false
        )
    }

    private func nativeFavoriteButton(
        in cell: NativeTrackTableCell
    ) throws -> NSButton {
        try #require(
            cell.subviews
                .compactMap { $0 as? NSButton }
                .first {
                    $0.accessibilityLabel() == "Add to Favorites"
                }
        )
    }

    private func nativeTextField(
        in cell: NativeTrackTableCell,
        value: String
    ) throws -> NSTextField {
        try #require(
            cell.subviews
                .compactMap { $0 as? NSTextField }
                .first { $0.stringValue == value }
        )
    }

    private func metadataCellWidth(_ field: NSTextField) -> CGFloat {
        field.cell?.cellSize.width ?? 0
    }

    private func nativeInteractionProjection(
        index: UInt8
    ) -> TrackRowDisplayProjection {
        TrackRowDisplayProjection(
            track: LibraryTrackProjection(
                id: deterministicUUID(90000 + Int(index)),
                title: "A deliberately long track title",
                artistID: deterministicUUID(91000 + Int(index)),
                artist: "Veilr",
                albumID: deterministicUUID(92000 + Int(index)),
                album: "Artificial Minds",
                duration: 195,
                year: 2025,
                codec: "FLAC",
                sampleRate: 44100,
                channelCount: 2,
                bitDepth: 24,
                isFavorite: false,
                isExplicit: false,
                customArtworkID: nil,
                artworkID: nil,
                relativeMediaPath: "fixture-\(index).flac",
                lastPlayedAt: nil,
                hasSynchronizedLyrics: true
            ),
            isCurrentTrack: false,
            isPlaying: false
        )
    }

    @Test("A native track cell keeps one layer and subview hierarchy")
    func nativeTrackCellKeepsStableHierarchy() {
        let probe = TrackTableWorkProbe()
        let cell = NativeTrackTableCell(
            frame: NSRect(x: 0, y: 0, width: 900, height: 58),
            probe: probe
        )
        let firstHierarchy = cell.renderHierarchyIdentity
        let tracks = makeTracks(count: 2)

        cell.configure(
            .track(
                TrackRowDisplayProjection(
                    track: tracks[0],
                    isCurrentTrack: false,
                    isPlaying: false
                )
            ),
            columns: [.album, .year, .time],
            widths: presentation.widths,
            isSelected: false,
            isFocused: false,
            isLiveScrolling: false
        )
        cell.configure(
            .track(
                TrackRowDisplayProjection(
                    track: tracks[1],
                    isCurrentTrack: true,
                    isPlaying: true
                )
            ),
            columns: [.album, .year, .time],
            widths: presentation.widths,
            isSelected: true,
            isFocused: true,
            isLiveScrolling: true
        )
        cell.layoutSubtreeIfNeeded()

        #expect(cell.wantsLayer)
        #expect(cell.layer != nil)
        #expect(cell.renderHierarchyIdentity == firstHierarchy)
        #expect(cell.representedTrackID == tracks[1].id)
        #expect(probe.nativeCellCreations == 1)
        #expect(probe.nativeCellConfigurations == 2)
        #expect(probe.nativeTrackIdentityChanges == 1)
        #expect(!containsHostingView(cell))
    }

    @Test("The native playback indicator uses three reusable animated bars")
    func nativePlaybackIndicatorLifecycle() {
        let indicator = NativePlaybackIndicatorView(
            frame: NSRect(x: 0, y: 0, width: 40, height: 40)
        )

        #expect(indicator.barCount == 3)
        #expect(!indicator.isAnimating)
        #expect(indicator.hitTest(NSPoint(x: 20, y: 20)) == nil)

        indicator.setPlaying(true, reduceMotion: false)
        #expect(indicator.isAnimating)
        let animationDurations = indicator.layer?.sublayers?.compactMap {
            $0.animation(
                forKey: "cadence.playback.level"
            ) as? CAKeyframeAnimation
        }.map(\.duration) ?? []
        #expect(animationDurations.count == 3)
        #expect(animationDurations.allSatisfy { $0 >= 1.15 })

        indicator.setPlaying(false, reduceMotion: false)
        #expect(!indicator.isAnimating)

        indicator.setPlaying(true, reduceMotion: true)
        #expect(!indicator.isAnimating)
    }

    @Test("A playing track cell renders the animated indicator above artwork")
    func nativeTrackCellUsesPlaybackIndicator() throws {
        let track = makeTracks(count: 1)[0]
        let cell = NativeTrackTableCell(
            frame: NSRect(x: 0, y: 0, width: 900, height: 58)
        )

        cell.configure(
            .track(
                TrackRowDisplayProjection(
                    track: track,
                    isCurrentTrack: true,
                    isPlaying: true
                )
            ),
            columns: [.album, .year, .time],
            widths: presentation.widths,
            isSelected: false,
            isFocused: false,
            isLiveScrolling: false
        )
        cell.layoutSubtreeIfNeeded()

        let indicator = try #require(
            cell.subviews
                .compactMap { $0 as? NativePlaybackIndicatorView }
                .first
        )
        #expect(!indicator.isHidden)
        #expect(indicator.isAnimating)
        #expect(indicator.frame == NSRect(x: 58, y: 9, width: 40, height: 40))
    }

    @Test("Native actions resolve the represented track after cell reuse")
    func nativeActionsFollowCellReuse() {
        let tracks = makeTracks(count: 2)
        let cell = NativeTrackTableCell()
        var actions: [(UUID, NativeTrackTableAction)] = []
        cell.onAction = { trackID, action in
            actions.append((trackID, action))
        }

        cell.configure(
            .track(
                TrackRowDisplayProjection(
                    track: tracks[0],
                    isCurrentTrack: false,
                    isPlaying: false
                )
            ),
            columns: [],
            widths: presentation.widths,
            isSelected: false,
            isFocused: false,
            isLiveScrolling: false
        )
        cell.performAction(.favorite)
        cell.configure(
            .track(
                TrackRowDisplayProjection(
                    track: tracks[1],
                    isCurrentTrack: false,
                    isPlaying: false
                )
            ),
            columns: [],
            widths: presentation.widths,
            isSelected: false,
            isFocused: false,
            isLiveScrolling: false
        )
        cell.performAction(.play)

        #expect(actions.count == 2)
        #expect(actions[0].0 == tracks[0].id)
        #expect(actions[0].1 == .favorite)
        #expect(actions[1].0 == tracks[1].id)
        #expect(actions[1].1 == .play)
    }

    @Test("Native play works outside playlist contexts")
    func nativePlayWorksInLibraryContext() async {
        let tracks = makeTracks(count: 2)
        let resolver = PlaybackTestResolver(
            tracks: tracks.map {
                playbackTestTrack(id: $0.id, title: $0.title)
            }
        )
        let backend = PlaybackTestBackend(kind: .pcm)
        let playbackCoordinator = makePlaybackCoordinator(
            resolver: resolver,
            backends: [backend]
        )
        let model = CadenceAppModel(
            runtimeEnvironment: .production,
            importRuntimeAvailability: .unavailable("Not used by this test."),
            librarySession: .preview(),
            playbackCoordinator: playbackCoordinator
        )
        let core = TrackTableCore(
            model: model,
            context: .library,
            snapshot: makeSnapshot(
                rows: tracks,
                version: TrackTableContentVersion(
                    sourceID: deterministicUUID(81011),
                    generation: 0
                )
            ),
            virtualWindow: nil,
            columns: [],
            widths: presentation.widths,
            playlistID: nil,
            queueSource: .adHoc,
            reorderAction: nil,
            onReachEnd: nil,
            selection: .constant([])
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)

        coordinator.play(row: 0)
        for _ in 0 ..< 500 where resolver.requests.isEmpty {
            await Task.yield()
        }

        #expect(resolver.requests == [tracks.map(\.id)])
        model.shutdownPlayback()
    }

    @Test("Selection-only native updates do not rewrite row content")
    func nativeSelectionUpdateTouchesChromeOnly() {
        let probe = TrackTableWorkProbe()
        let cell = NativeTrackTableCell(probe: probe)
        let projection = TrackRowDisplayProjection(
            track: makeTracks(count: 1)[0],
            isCurrentTrack: false,
            isPlaying: false
        )

        cell.configure(
            .track(projection),
            columns: [.album, .year, .time],
            widths: presentation.widths,
            isSelected: false,
            isFocused: false,
            isLiveScrolling: false
        )
        cell.configure(
            .track(projection),
            columns: [.album, .year, .time],
            widths: presentation.widths,
            isSelected: true,
            isFocused: true,
            isLiveScrolling: false
        )

        #expect(probe.nativeCellConfigurations == 2)
        #expect(probe.nativeContentApplications == 1)
        #expect(probe.nativeLayoutInvalidations == 1)
    }

    @Test("Display projections stay bounded and hit on scroll-only reuse")
    func displayProjectionCacheIsBounded() {
        let tracks = makeTracks(count: 12)
        let probe = TrackTableWorkProbe()
        let cache = TrackRowDisplayProjectionCache(
            capacity: 4,
            probe: probe
        )

        for track in tracks.prefix(4) {
            _ = cache.resolve(
                track: track,
                currentTrackID: nil,
                isCurrentTrackPlaying: false
            )
        }
        _ = cache.resolve(
            track: tracks[1],
            currentTrackID: nil,
            isCurrentTrackPlaying: false
        )
        for track in tracks.dropFirst(4) {
            _ = cache.resolve(
                track: track,
                currentTrackID: nil,
                isCurrentTrackPlaying: false
            )
        }

        #expect(cache.count == 4)
        #expect(probe.displayProjectionBuilds == 12)
        #expect(probe.displayProjectionCacheHits == 1)
    }

    @Test("Display projection overflow keeps the newest resident rows")
    func displayProjectionCacheRetainsNewestRows() {
        let tracks = makeTracks(count: 5)
        let probe = TrackTableWorkProbe()
        let cache = TrackRowDisplayProjectionCache(
            capacity: 3,
            probe: probe
        )

        for track in tracks.prefix(4) {
            _ = cache.resolve(
                track: track,
                currentTrackID: nil,
                isCurrentTrackPlaying: false
            )
        }
        _ = cache.resolve(
            track: tracks[3],
            currentTrackID: nil,
            isCurrentTrackPlaying: false
        )
        _ = cache.resolve(
            track: tracks[0],
            currentTrackID: nil,
            isCurrentTrackPlaying: false
        )

        #expect(cache.count == 3)
        #expect(probe.displayProjectionBuilds == 5)
        #expect(probe.displayProjectionCacheHits == 1)
    }

    @Test("Appending materialized rows inserts only the new tail")
    func materializedAppendUsesRowInsertion() {
        let rows = makeTracks(count: 8)
        let sourceID = deterministicUUID(81005)
        let previous = TrackTableRenderedState(
            source: .materialized(
                makeSnapshot(
                    rows: Array(rows.prefix(5)),
                    version: TrackTableContentVersion(
                        sourceID: sourceID,
                        generation: 0
                    )
                )
            ),
            selection: [],
            presentation: presentation
        )

        let plan = TrackTableUpdatePlanner.plan(
            previous: previous,
            source: .materialized(
                makeSnapshot(
                    rows: rows,
                    version: TrackTableContentVersion(
                        sourceID: sourceID,
                        generation: 1
                    )
                )
            ),
            selection: [],
            presentation: presentation,
            visibleRows: IndexSet(integersIn: 0 ..< 5)
        )

        #expect(
            plan.reload == .changes(
                TrackTableChanges(
                    insertedRows: IndexSet(integersIn: 5 ..< 8)
                )
            )
        )
        #expect(plan.resetsEndPaging)
    }

    @Test("Native drag payload preserves selected playlist order")
    func nativeDragDropUsesStableTrackIDs() throws {
        let rows = makeTracks(count: 6)
        let version = TrackTableContentVersion(
            sourceID: deterministicUUID(81006),
            generation: 0
        )
        var selection: Set<UUID> = [rows[1].id, rows[3].id]
        var reorderedIDs: [UUID] = []
        let core = TrackTableCore(
            model: presentationModel,
            context: .library,
            snapshot: makeSnapshot(rows: rows, version: version),
            virtualWindow: nil,
            columns: [],
            widths: presentation.widths,
            playlistID: nil,
            queueSource: .allTracks,
            reorderAction: { reorderedIDs = $0 },
            onReachEnd: nil,
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = NSTableView()

        let item = try #require(
            coordinator.tableView(
                tableView,
                pasteboardWriterForRow: 1
            ) as? NSPasteboardItem
        )
        let payload = try #require(item.string(forType: .string))
        #expect(
            coordinator.acceptNativeDrop(
                payload: payload,
                beforeRow: 5
            )
        )
        #expect(
            reorderedIDs == [
                rows[0].id,
                rows[2].id,
                rows[4].id,
                rows[1].id,
                rows[3].id,
                rows[5].id,
            ]
        )
    }

    @Test("Late native artwork cannot overwrite a reused cell")
    func nativeArtworkRejectsStaleResults() async throws {
        let loader = SuspendedTrackArtworkLoader()
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 1,
                pixelsHigh: 1,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let artworkData = try #require(
            representation.representation(using: .png, properties: [:])
        )
        let tracks = makeTracks(count: 2)
        let firstArtworkID = deterministicUUID(81008)
        let secondArtworkID = deterministicUUID(81009)
        let first = replacingArtworkID(tracks[0], with: firstArtworkID)
        let second = replacingArtworkID(tracks[1], with: secondArtworkID)
        let cell = NativeTrackTableCell(
            frame: NSRect(x: 0, y: 0, width: 900, height: 58)
        )
        let window = NSWindow(
            contentRect: cell.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = cell
        window.orderFront(nil)
        defer {
            loader.releaseAll()
            window.orderOut(nil)
            window.close()
        }
        let artworkLoader: NativeTrackArtworkLoader = { artworkID, variant in
            await loader.load(artworkID: artworkID, variant: variant)
        }

        configureNativeCell(cell, track: first, loader: artworkLoader)
        for _ in 0 ..< 100 where !loader.hasStarted(firstArtworkID) {
            try await Task.sleep(for: .milliseconds(10))
        }
        configureNativeCell(cell, track: second, loader: artworkLoader)
        for _ in 0 ..< 100 where !loader.hasStarted(secondArtworkID) {
            try await Task.sleep(for: .milliseconds(10))
        }
        loader.release(
            secondArtworkID,
            asset: ArtworkAsset(
                id: secondArtworkID,
                data: artworkData,
                variant: .trackRow
            )
        )
        for _ in 0 ..< 100
            where cell.publishedArtworkRequest?.artworkID != secondArtworkID {
            try await Task.sleep(for: .milliseconds(10))
        }
        loader.release(
            firstArtworkID,
            asset: ArtworkAsset(
                id: firstArtworkID,
                data: artworkData,
                variant: .trackRow
            )
        )
        for _ in 0 ..< 100
            where loader.observedCancellation(for: firstArtworkID) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(loader.observedCancellation(for: firstArtworkID) == true)
        #expect(cell.representedTrackID == second.id)
        #expect(cell.publishedArtworkRequest?.artworkID == secondArtworkID)
    }

    @Test("Native artwork applies the saved crop in its layer")
    func nativeArtworkAppliesCrop() async throws {
        let artworkID = deterministicUUID(81010)
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2,
                pixelsHigh: 1,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let data = try #require(
            representation.representation(using: .png, properties: [:])
        )
        let track = replacingArtworkID(
            makeTracks(count: 1)[0],
            with: artworkID
        )
        let cell = NativeTrackTableCell()
        configureNativeCell(cell, track: track) { _, variant in
            ArtworkAsset(
                id: artworkID,
                data: data,
                variant: variant,
                scale: 2,
                normalizedOffset: CGSize(width: 0.25, height: 0)
            )
        }

        for _ in 0 ..< 500
            where cell.publishedArtworkRequest?.artworkID != artworkID {
            await Task.yield()
        }

        #expect(cell.publishedArtworkRequest?.artworkID == artworkID)
        #expect(
            cell.publishedArtworkContentsRect
                == CGRect(x: 0.3125, y: 0.25, width: 0.25, height: 0.5)
        )
    }

    @Test("The production table factory returns native layer-backed cells")
    func productionTableUsesNativeCells() throws {
        let tracks = makeTracks(count: 2)
        let probe = TrackTableWorkProbe()
        let core = TrackTableCore(
            model: presentationModel,
            context: .library,
            snapshot: makeSnapshot(
                rows: tracks,
                version: TrackTableContentVersion(
                    sourceID: deterministicUUID(81004),
                    generation: 0
                )
            ),
            virtualWindow: nil,
            columns: [.album, .year, .time],
            widths: presentation.widths,
            playlistID: nil,
            queueSource: .allTracks,
            reorderAction: nil,
            onReachEnd: nil,
            renderer: .native,
            workProbe: probe,
            selection: .constant([])
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = NSTableView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 116)
        )
        let column = NSTableColumn(identifier: .init("row"))
        tableView.addTableColumn(column)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator

        let cell = try #require(
            coordinator.tableView(
                tableView,
                viewFor: column,
                row: 0
            ) as? NativeTrackTableCell
        )

        #expect(cell.representedTrackID == tracks[0].id)
        #expect(cell.wantsLayer)
        #expect(probe.nativeCellCreations == 1)
        #expect(probe.hostingRootInstalls == 0)
    }

    @Test("A real 10k production table measures the native renderer")
    func realWindowMeasuresProductionNativeRenderer() {
        let fixture = NativeProductionTrackScrollFixture(tests: self)
        defer { fixture.finish() }

        let reports = fixture.measureAllProfiles()
        for report in reports {
            print(report.diagnostic(mode: "production-native-layer-backed"))
        }

        let sequential = reports.first
        #expect((sequential?.p95Milliseconds ?? .infinity) < 1000 / 60)
        #expect(
            Double(fixture.probe.maximumNativeConfigurationNanoseconds)
                / 1_000_000 < 1000 / 120
        )
        #expect(fixture.probe.nativeCellCreations > 0)
        #expect(
            fixture.probe.nativeCellCreations
                < fixture.probe.nativeCellConfigurations
        )
        #expect(fixture.probe.hostingRootInstalls == 0)
        #expect(fixture.reusedCellCount > 0)
    }

    @Test(
        "Real AppKit updates bound no-op and visible row work",
        arguments: [1000, 10000]
    )
    func realAppKitUpdateWorkMatrix(count: Int) throws {
        let fixture = try RealAppKitUpdateFixture(count: count, tests: self)
        defer { fixture.detach() }

        fixture.verifyNoOpUpdates()
        fixture.verifySelectionUpdate()
        fixture.verifyTrackMutation()
        fixture.verifyPresentationResize()
        try fixture.verifyCellReuse()
    }

    @Test("A presentation change reconfigures only visible rows")
    func presentationChangeReconfiguresVisibleRowsOnly() {
        let rows = makeTracks(count: 1000)
        let version = TrackTableContentVersion(
            sourceID: deterministicUUID(50002),
            generation: 0
        )
        let snapshot = makeSnapshot(rows: rows, version: version)
        let previous = TrackTableRenderedState(
            source: .materialized(snapshot),
            selection: [],
            presentation: presentation
        )
        let visibleRows = IndexSet(integersIn: 400 ..< 424)
        let probe = TrackTableWorkProbe()

        let plan = TrackTableUpdatePlanner.plan(
            previous: previous,
            source: .materialized(snapshot),
            selection: [],
            presentation: presentationWithSongWidth(420),
            visibleRows: visibleRows,
            probe: probe
        )

        #expect(plan.reload == .rows(visibleRows))
        #expect(probe.sortPasses == 0)
        #expect(probe.rowComparisons == 0)
        #expect(!plan.requestsViewport)
    }

    @Test("Virtual revisions compare only configured visible stamps")
    func virtualRevisionChecksOnlyVisibleStamps() {
        let window = LibraryTrackWindow { _, _, _ in [] }
        let identity = TrackTableVirtualIdentity(
            windowID: ObjectIdentifier(window),
            query: .allTracks,
            totalCount: 1_000_000
        )
        let visibleRows = IndexSet(integersIn: 400 ..< 424)
        let placeholders = Dictionary(
            uniqueKeysWithValues: visibleRows.map {
                ($0, TrackTableRowStamp.placeholder)
            }
        )
        let previous = TrackTableRenderedState(
            source: .virtual(
                identity: identity,
                revision: 1,
                stamps: placeholders
            ),
            selection: [],
            presentation: presentation
        )
        let probe = TrackTableWorkProbe()
        let offscreenPlan = TrackTableUpdatePlanner.plan(
            previous: previous,
            source: .virtual(
                identity: identity,
                revision: 2,
                stamps: placeholders
            ),
            selection: [],
            presentation: presentation,
            visibleRows: visibleRows,
            probe: probe
        )

        #expect(offscreenPlan.reload == .none)
        #expect(offscreenPlan.requestsViewport)
        #expect(probe.virtualStampComparisons == 24)

        var loadedStamps = placeholders
        loadedStamps[411] = .track(makeTracks(count: 412)[411])
        let visiblePlan = TrackTableUpdatePlanner.plan(
            previous: TrackTableRenderedState(
                source: .virtual(
                    identity: identity,
                    revision: 2,
                    stamps: placeholders
                ),
                selection: [],
                presentation: presentation
            ),
            source: .virtual(
                identity: identity,
                revision: 3,
                stamps: loadedStamps
            ),
            selection: [],
            presentation: presentation,
            visibleRows: visibleRows,
            probe: probe
        )

        #expect(visiblePlan.reload == .rows(IndexSet(integer: 411)))
        #expect(probe.virtualStampComparisons == 48)
    }

    @Test("A bounds event cannot commit virtual rows before cells render them")
    func boundsEventDoesNotAcknowledgeUnrenderedVirtualRows() async throws {
        let rows = makeTracks(count: 24)
        let source = MutableTrackWindowSource()
        let window = LibraryTrackWindow(
            pageSize: 24,
            pageCapacity: 3,
            prefetchPages: 0
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        let initialVersion = TrackTableContentVersion(
            sourceID: deterministicUUID(20000),
            generation: 0
        )
        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: initialVersion
        )

        var selection: Set<UUID> = []
        let probe = TrackTableWorkProbe()
        let core = makeVirtualCore(
            window: window,
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            probe: probe
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = RecordingTrackTableView(
            visibleRows: NSRange(location: 0, length: rows.count)
        )
        tableView.frame = NSRect(
            x: 0,
            y: 0,
            width: 900,
            height: CGFloat(rows.count) * 58
        )
        tableView.rowHeight = 58
        let column = NSTableColumn(identifier: .init("row"))
        tableView.addTableColumn(column)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 24 * 58)
        )
        scrollView.documentView = tableView
        coordinator.attach(tableView: tableView, scrollView: scrollView)
        defer { coordinator.detach() }

        var placeholderCells: [NSView] = []
        for row in rows.indices {
            try placeholderCells.append(
                #require(
                    coordinator.tableView(
                        tableView,
                        viewFor: column,
                        row: row
                    )
                )
            )
        }
        let visibleRows = IndexSet(integersIn: rows.indices)
        coordinator.renderedState = TrackTableRenderedState(
            source: coordinator.renderedSource(
                for: core,
                visibleRows: visibleRows
            ),
            selection: [],
            presentation: core.presentation
        )

        await source.replace(with: rows)
        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: initialVersion.advanced()
        )
        coordinator.visibleBoundsChanged()

        tableView.reusableViews = placeholderCells
        tableView.reloadHandler = { rowIndexes in
            for row in rowIndexes {
                _ = coordinator.tableView(
                    tableView,
                    viewFor: column,
                    row: row
                )
            }
        }
        core.applyUpdate(to: scrollView, coordinator: coordinator)

        #expect(tableView.reloadedRowSets == [visibleRows])
        #expect(probe.appliedUpdates == 1)
        #expect(probe.pageTaskStarts == 0)
        #expect(probe.reloadBatches == 1)
        #expect(probe.reloadedRows == rows.count)
        #expect(probe.hostingRootInstalls == rows.count)
        #expect(probe.hostConfigurations == rows.count * 2)
    }

    @Test(
        "Vertical bounds ticks do not rewrite unchanged table geometry",
        arguments: [1000, 10000]
    )
    func verticalBoundsTicksDoNotRewriteGeometry(
        count: Int
    ) throws {
        let rows = makeTracks(count: count)
        let probe = TrackTableWorkProbe()
        let core = makeCore(
            rows: rows,
            selection: .constant([]),
            probe: probe,
            sourceIndex: count + 70000
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = ScrollLifecycleRecordingTrackTableView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 900,
                height: CGFloat(count) * 58
            )
        )
        tableView.rowHeight = 58
        let column = NSTableColumn(identifier: .init("row"))
        tableView.addTableColumn(column)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator

        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 24 * 58)
        )
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true
        coordinator.attach(tableView: tableView, scrollView: scrollView)
        defer { coordinator.detach() }

        let visibleRows = coordinator.visibleRowIndexes()
        var cells: [TrackTableHostingCell] = []
        for row in visibleRows {
            try cells.append(
                #require(
                    coordinator.tableView(
                        tableView,
                        viewFor: column,
                        row: row
                    ) as? TrackTableHostingCell
                )
            )
        }
        let source = coordinator.renderedSource(
            for: core,
            visibleRows: visibleRows
        )
        coordinator.renderedState = TrackTableRenderedState(
            source: source,
            selection: [],
            presentation: core.presentation
        )
        let cellIDs = cells.map(ObjectIdentifier.init)
        scrollView.layoutSubtreeIfNeeded()
        coordinator.updateColumnWidth()
        probe.reset()
        tableView.resetFrameSizeWrites()

        for tick in 0 ..< 100 {
            scrollView.contentView.postsBoundsChangedNotifications = false
            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: CGFloat(tick % 12))
            )
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.post(
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        #expect(tableView.frameSizeWrites == 0)
        #expect(probe.fullReloads == 0)
        #expect(probe.reloadBatches == 0)
        #expect(probe.selectionRestores == 0)
        #expect(probe.hostConfigurations == 0)
        #expect(cells.map(ObjectIdentifier.init) == cellIDs)
    }

    @Test(
        "Cached virtual bounds ticks settle after one directional prefetch",
        arguments: [1000, 10000]
    )
    func cachedVirtualBoundsTicksDoNotSchedulePageTasks(
        count: Int
    ) async throws {
        let rows = makeTracks(count: count)
        let loadCounter = TrackWindowLoadCounter()
        let window = LibraryTrackWindow(
            pageSize: 12,
            pageCapacity: 3,
            prefetchPages: 1
        ) { _, offset, limit in
            await loadCounter.record(offset: offset, limit: limit)
            return Array(rows[offset ..< min(offset + limit, rows.count)])
        }
        await window.configure(
            totalCount: count,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(count + 80000),
                generation: 0
            )
        )
        #expect(await loadCounter.requests == [0, 12])

        let probe = TrackTableWorkProbe()
        let core = makeVirtualCore(
            window: window,
            selection: .constant([]),
            probe: probe
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let fixedVisibleRows = NSRange(location: 0, length: 24)
        let tableView = ScrollLifecycleRecordingTrackTableView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 900,
                height: CGFloat(count) * 58
            ),
            visibleRows: fixedVisibleRows
        )
        tableView.rowHeight = 58
        let column = NSTableColumn(identifier: .init("row"))
        tableView.addTableColumn(column)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator

        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 24 * 58)
        )
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true
        coordinator.attach(tableView: tableView, scrollView: scrollView)
        defer { coordinator.detach() }

        let visibleRows = IndexSet(integersIn: 0 ..< 24)
        var cells: [TrackTableHostingCell] = []
        for row in visibleRows {
            try cells.append(
                #require(
                    coordinator.tableView(
                        tableView,
                        viewFor: column,
                        row: row
                    ) as? TrackTableHostingCell
                )
            )
        }
        let source = coordinator.renderedSource(
            for: core,
            visibleRows: visibleRows
        )
        coordinator.renderedState = TrackTableRenderedState(
            source: coordinator.committedSource(
                after: source,
                visibleRows: visibleRows
            ),
            selection: [],
            presentation: core.presentation
        )
        scrollView.layoutSubtreeIfNeeded()
        coordinator.updateColumnWidth()
        probe.reset()
        tableView.resetFrameSizeWrites()
        let scheduledPageTasks = await runCachedBoundsTicks(
            core: core,
            coordinator: coordinator,
            scrollView: scrollView
        )

        #expect(scheduledPageTasks == 1)
        #expect(probe.appliedUpdates == 100)
        #expect(probe.pageTaskStarts == 1)
        #expect(probe.virtualStampReads == 24)
        #expect(probe.viewportRequests == 2)
        #expect(await loadCounter.requests == [0, 12, 24])
        #expect(tableView.frameSizeWrites == 0)
        #expect(probe.fullReloads == 0)
        #expect(probe.reloadBatches == 0)
        #expect(probe.selectionRestores == 0)
        #expect(probe.hostConfigurations == 0)
        #expect(cells.count == 24)
    }

    private func runCachedBoundsTicks(
        core: TrackTableCore,
        coordinator: TrackTableCore.Coordinator,
        scrollView: NSScrollView
    ) async -> Int {
        var scheduledPageTasks = 0
        for tick in 0 ..< 100 {
            scrollView.contentView.postsBoundsChangedNotifications = false
            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: CGFloat(tick % 12))
            )
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.post(
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            core.applyUpdate(to: scrollView, coordinator: coordinator)
            scheduledPageTasks += coordinator.pendingPages.count
            while !coordinator.pendingPages.isEmpty {
                await Task.yield()
            }
        }
        return scheduledPageTasks
    }

    @Test(
        "A viewport fling cancels obsolete page loads before they enter the cache"
    )
    func viewportFlingCancelsObsoletePageLoads() async throws {
        let rows = makeTracks(count: 300)
        let source = SuspendedFlingTrackWindowSource(rows: rows)
        let window = LibraryTrackWindow(
            pageSize: 12,
            pageCapacity: 2,
            prefetchPages: 0
        ) { _, offset, limit in
            await source.rows(offset: offset, limit: limit)
        }
        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(80003),
                generation: 0
            )
        )

        let core = makeVirtualCore(
            window: window,
            selection: .constant([]),
            probe: nil
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = RecordingTrackTableView(
            visibleRows: NSRange(location: 12, length: 12)
        )
        tableView.addTableColumn(NSTableColumn(identifier: .init("row")))
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 12 * 58)
        )
        scrollView.documentView = tableView
        coordinator.attach(tableView: tableView, scrollView: scrollView)
        defer {
            source.releaseAll()
            coordinator.detach()
        }

        coordinator.visibleBoundsChanged()
        await source.waitUntilStarted(offset: 12)
        let firstTask = try #require(coordinator.pendingPages[1])

        tableView.recordedVisibleRows = NSRange(location: 120, length: 12)
        coordinator.visibleBoundsChanged()
        await source.waitUntilStarted(offset: 120)
        let middleTask = try #require(coordinator.pendingPages[10])

        tableView.recordedVisibleRows = NSRange(location: 240, length: 12)
        coordinator.visibleBoundsChanged()
        await source.waitUntilStarted(offset: 240)
        let currentTask = try #require(coordinator.pendingPages[20])

        #expect(Set(coordinator.pendingPages.keys) == [20])
        #expect(firstTask.isCancelled)
        #expect(middleTask.isCancelled)
        #expect(!currentTask.isCancelled)

        source.release(offset: 12)
        source.release(offset: 120)
        await firstTask.value
        await middleTask.value

        #expect(source.observedCancellation(offset: 12) == true)
        #expect(source.observedCancellation(offset: 120) == true)
        #expect(window.track(at: 12) == nil)
        #expect(window.track(at: 120) == nil)

        source.release(offset: 240)
        await currentTask.value

        #expect(window.track(at: 240) == rows[240])
    }

    @Test("An unchanged viewport retries a failed virtual page")
    func unchangedViewportRetriesFailedVirtualPage() async {
        let rows = makeTracks(count: 24)
        let source = RetryOnceTrackWindowSource(
            rows: rows,
            failingOffset: 12
        )
        let window = LibraryTrackWindow(
            pageSize: 12,
            pageCapacity: 2,
            prefetchPages: 0
        ) { _, offset, limit in
            try await source.rows(offset: offset, limit: limit)
        }
        await window.configure(
            totalCount: rows.count,
            query: .allTracks,
            contentVersion: TrackTableContentVersion(
                sourceID: deterministicUUID(80003),
                generation: 0
            )
        )

        let core = makeVirtualCore(
            window: window,
            selection: .constant([]),
            probe: nil
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = RecordingTrackTableView(
            visibleRows: NSRange(location: 12, length: 12)
        )
        tableView.addTableColumn(NSTableColumn(identifier: .init("row")))
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 12 * 58)
        )
        scrollView.documentView = tableView
        coordinator.attach(tableView: tableView, scrollView: scrollView)
        defer { coordinator.detach() }

        coordinator.visibleBoundsChanged()
        while !coordinator.pendingPages.isEmpty {
            await Task.yield()
        }
        #expect(window.track(at: 12) == nil)
        #expect(await source.attemptCount(offset: 12) == 1)

        coordinator.visibleBoundsChanged()
        while !coordinator.pendingPages.isEmpty {
            await Task.yield()
        }

        #expect(window.track(at: 12) == rows[12])
        #expect(await source.attemptCount(offset: 12) == 2)
    }
}

@MainActor
private final class NativeProductionTrackScrollFixture {
    private static let rowCount = 10000
    private let rows: [LibraryTrackProjection]
    private let selectionBox: NativeTrackSelectionBox
    let probe: TrackTableWorkProbe
    private let core: TrackTableCore
    private let coordinator: TrackTableCore.Coordinator
    private let tableView = TrackTableView()
    private let scrollView: NSScrollView
    private let window: NSWindow
    private var trackIDsByCell: [ObjectIdentifier: Set<UUID>] = [:]

    init(tests: AllTracksPerformanceTests) {
        let rows = tests.makeTracks(count: Self.rowCount)
        let selectionBox = NativeTrackSelectionBox()
        let probe = TrackTableWorkProbe()
        let snapshot = tests.makeSnapshot(
            rows: rows,
            version: TrackTableContentVersion(
                sourceID: tests.deterministicUUID(81100),
                generation: 0
            )
        )
        let viewport = NSRect(x: 0, y: 0, width: 900, height: 18 * 58)
        let scrollView = NSScrollView(frame: viewport)
        let window = NSWindow(
            contentRect: viewport,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let core = TrackTableCore(
            model: tests.presentationModel,
            context: .library,
            snapshot: snapshot,
            virtualWindow: nil,
            columns: TrackTableColumn.allCases,
            widths: tests.presentation.widths,
            playlistID: nil,
            queueSource: .allTracks,
            reorderAction: nil,
            onReachEnd: nil,
            renderer: .native,
            workProbe: probe,
            selection: selectionBox.binding
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)

        self.rows = rows
        self.selectionBox = selectionBox
        self.probe = probe
        self.core = core
        self.coordinator = coordinator
        self.scrollView = scrollView
        self.window = window

        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.rowHeight = 58
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        let column = NSTableColumn(
            identifier: TrackTableCore.Coordinator.columnIdentifier
        )
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true
        coordinator.attach(tableView: tableView, scrollView: scrollView)

        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFront(nil)
        tableView.reloadData()
        settleAppKit()
        recordVisibleCells()
    }

    var reusedCellCount: Int {
        trackIDsByCell.values.filter { $0.count > 1 }.count
    }

    func finish() {
        coordinator.detach()
        tableView.dataSource = nil
        tableView.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    func measureAllProfiles() -> [RealWindowScrollTimingReport] {
        RealWindowScrollProfile.allCases.map(measure)
    }

    private func measure(
        _ profile: RealWindowScrollProfile
    ) -> RealWindowScrollTimingReport {
        tableView.scrollRowToVisible(profile.warmupRow)
        settleAppKit()
        for _ in 0 ..< 3 {
            tableView.scrollRowToVisible(targetRow(for: profile))
            settleAppKit()
        }
        let configurationsBefore = probe.nativeCellConfigurations
        let creationsBefore = probe.nativeCellCreations
        let identityChangesBefore = probe.nativeTrackIdentityChanges
        let durations = (0 ..< profile.sampleCount).map { _ in
            let started = DispatchTime.now().uptimeNanoseconds
            tableView.scrollRowToVisible(targetRow(for: profile))
            settleAppKit()
            recordVisibleCells()
            return Double(
                DispatchTime.now().uptimeNanoseconds - started
            ) / 1_000_000
        }
        return RealWindowScrollTimingReport(
            profile: profile,
            durations: durations,
            newConfigurations:
            probe.nativeCellConfigurations - configurationsBefore,
            newRoots: probe.nativeCellCreations - creationsBefore,
            identityChanges:
            probe.nativeTrackIdentityChanges - identityChangesBefore
        )
    }

    private func targetRow(
        for profile: RealWindowScrollProfile
    ) -> Int {
        let visibleRows = tableView.rows(in: scrollView.contentView.bounds)
        return profile.targetRow(
            visibleRows: visibleRows,
            rowCount: rows.count
        )
    }

    private func recordVisibleCells() {
        let range = tableView.rows(in: scrollView.contentView.bounds)
        guard range.location != NSNotFound else {
            return
        }
        let upperBound = min(range.location + range.length, rows.count)
        for row in range.location ..< upperBound {
            guard let cell = tableView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
            ) as? NativeTrackTableCell else {
                continue
            }
            trackIDsByCell[ObjectIdentifier(cell), default: []]
                .insert(rows[row].id)
        }
    }

    private func settleAppKit() {
        scrollView.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        _ = RunLoop.main.run(
            mode: .default,
            before: Date(timeIntervalSinceNow: 0.001)
        )
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
}

@MainActor
private final class NativeTrackSelectionBox {
    var selection: Set<UUID> = []

    var binding: Binding<Set<UUID>> {
        Binding(
            get: { self.selection },
            set: { self.selection = $0 }
        )
    }
}

@MainActor
private func containsHostingView(_ view: NSView) -> Bool {
    if String(describing: type(of: view)).contains("NSHostingView") {
        return true
    }
    return view.subviews.contains(where: containsHostingView)
}

@MainActor
private func configureNativeCell(
    _ cell: NativeTrackTableCell,
    track: LibraryTrackProjection,
    loader: @escaping NativeTrackArtworkLoader
) {
    cell.configure(
        .track(
            TrackRowDisplayProjection(
                track: track,
                isCurrentTrack: false,
                isPlaying: false
            )
        ),
        columns: [],
        widths: TrackTableColumnPolicy.defaultWidths,
        isSelected: false,
        isFocused: false,
        isLiveScrolling: false,
        artworkLoader: loader
    )
}

@MainActor
private final class RealAppKitUpdateFixture {
    let count: Int
    let tests: AllTracksPerformanceTests
    let state: RealAppKitUpdateState
    let probe: TrackTableWorkProbe
    let projectionCache: TrackTableProjectionCache
    let coordinator: TrackTableCore.Coordinator
    let tableView: RecordingTrackTableView
    let scrollView: NSScrollView
    let column: NSTableColumn

    var core: TrackTableCore
    var cellsByRow: [Int: TrackTableHostingCell] = [:]
    var initialRootIDs: Set<ObjectIdentifier> = []

    init(
        count: Int,
        tests: AllTracksPerformanceTests
    ) throws {
        let rows = tests.makeTracks(count: count)
        let state = RealAppKitUpdateState(
            rows: rows,
            selection: [rows[0].id],
            version: TrackTableContentVersion(
                sourceID: tests.deterministicUUID(count + 90000),
                generation: 0
            )
        )
        let probe = TrackTableWorkProbe()
        let projectionCache = TrackTableProjectionCache(probe: probe)
        let core = tests.makeCore(
            snapshot: projectionCache.resolve(
                rows: state.rows,
                contentVersion: state.version,
                sortDescriptor: tests.titleSort,
                repositoryOrdered: false
            ),
            selection: state.selectionBinding,
            probe: probe,
            widths: tests.presentation.widths
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = RecordingTrackTableView(
            visibleRows: NSRange(location: 0, length: 24)
        )
        let column = NSTableColumn(identifier: .init("row"))
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 24 * 58)
        )

        self.count = count
        self.tests = tests
        self.state = state
        self.probe = probe
        self.projectionCache = projectionCache
        self.core = core
        self.coordinator = coordinator
        self.tableView = tableView
        self.scrollView = scrollView
        self.column = column

        tableView.frame = NSRect(
            x: 0,
            y: 0,
            width: 900,
            height: CGFloat(count) * 58
        )
        tableView.rowHeight = 58
        tableView.addTableColumn(column)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        scrollView.documentView = tableView
        coordinator.attach(tableView: tableView, scrollView: scrollView)
        tableView.selectRowIndexes(
            IndexSet(integer: 0),
            byExtendingSelection: false
        )

        for row in 0 ..< 24 {
            cellsByRow[row] = try #require(
                coordinator.tableView(
                    tableView,
                    viewFor: column,
                    row: row
                ) as? TrackTableHostingCell
            )
        }
        let visibleRows = IndexSet(integersIn: 0 ..< 24)
        coordinator.renderedState = TrackTableRenderedState(
            source: coordinator.renderedSource(
                for: core,
                visibleRows: visibleRows
            ),
            selection: state.selection,
            presentation: core.presentation
        )
        coordinator.updateColumnWidth()
        initialRootIDs = Set(
            cellsByRow.values.map { ObjectIdentifier($0.hostState) }
        )
        tableView.reloadHandler = { [weak self] rowIndexes in
            self?.reload(rowIndexes)
        }
    }

    func detach() {
        coordinator.detach()
    }

    func verifyNoOpUpdates() {
        probe.reset()
        for _ in 0 ..< 100 {
            core = tests.makeCore(
                snapshot: projectionCache.resolve(
                    rows: state.rows,
                    contentVersion: state.version,
                    sortDescriptor: tests.titleSort,
                    repositoryOrdered: false
                ),
                selection: state.selectionBinding,
                probe: probe,
                widths: tests.presentation.widths
            )
            core.applyUpdate(to: scrollView, coordinator: coordinator)
        }

        #expect(probe.appliedUpdates == 100)
        #expect(probe.sortPasses == 0)
        #expect(probe.rowComparisons == 0)
        #expect(probe.fullReloads == 0)
        #expect(probe.reloadBatches == 0)
        #expect(probe.reloadedRows == 0)
        #expect(probe.selectionRestores == 0)
        #expect(probe.viewportRequests == 0)
        #expect(probe.hostingRootInstalls == 0)
        #expect(probe.hostConfigurations == 0)
        #expect(probe.tableFrameWrites == 0)
        #expect(probe.columnWidthWrites == 0)
        #expect(probe.pageTaskStarts == 0)
        #expect(probe.hostTrackIdentityChanges == 0)
        #expect(
            Set(cellsByRow.values.map { ObjectIdentifier($0.hostState) })
                == initialRootIDs
        )
    }

    func verifySelectionUpdate() {
        state.selection = [state.rows[1].id]
        probe.reset()
        core.applyUpdate(to: scrollView, coordinator: coordinator)

        #expect(probe.appliedUpdates == 1)
        #expect(probe.reloadBatches == 1)
        #expect(probe.reloadedRows == 2)
        #expect(probe.selectionRestores == 1)
        #expect(probe.hostConfigurations == 2)
        #expect(probe.hostTrackIdentityChanges == 0)
        #expect(tableView.selectedRowIndexes == IndexSet(integer: 1))
    }

    func verifyTrackMutation() {
        state.rows[5] = tests.togglingFavorite(state.rows[5])
        state.version = state.version.advanced()
        probe.reset()
        core = tests.makeCore(
            snapshot: projectionCache.resolve(
                rows: state.rows,
                contentVersion: state.version,
                sortDescriptor: tests.titleSort,
                repositoryOrdered: false
            ),
            selection: state.selectionBinding,
            probe: probe,
            widths: tests.presentation.widths
        )
        core.applyUpdate(to: scrollView, coordinator: coordinator)

        #expect(probe.appliedUpdates == 1)
        #expect(probe.sortPasses == 1)
        #expect(probe.rowComparisons == count)
        #expect(probe.reloadBatches == 1)
        #expect(probe.reloadedRows == 1)
        #expect(probe.hostConfigurations == 1)
        #expect(probe.hostTrackIdentityChanges == 0)
        #expect(cellsByRow[5]?.hostState.trackID == state.rows[5].id)
    }

    func verifyPresentationResize() {
        let widths = tests.presentation.widths
        let resizedWidths = TrackTableResolvedWidths(
            song: widths.song + 60,
            album: widths.album,
            year: widths.year,
            time: widths.time
        )
        probe.reset()
        core = tests.makeCore(
            snapshot: projectionCache.resolve(
                rows: state.rows,
                contentVersion: state.version,
                sortDescriptor: tests.titleSort,
                repositoryOrdered: false
            ),
            selection: state.selectionBinding,
            probe: probe,
            widths: resizedWidths
        )
        core.applyUpdate(to: scrollView, coordinator: coordinator)

        #expect(probe.appliedUpdates == 1)
        #expect(probe.sortPasses == 0)
        #expect(probe.reloadBatches == 1)
        #expect(probe.reloadedRows == 24)
        #expect(probe.hostConfigurations == 24)
        #expect(probe.hostTrackIdentityChanges == 0)
        #expect(probe.tableFrameWrites == 0)
        #expect(probe.columnWidthWrites == 0)
    }

    func verifyCellReuse() throws {
        tableView.recordedVisibleRows = NSRange(location: 24, length: 24)
        tableView.reusableViews = (0 ..< 24).compactMap { cellsByRow[$0] }
        probe.reset()
        var secondWindowCells: [TrackTableHostingCell] = []
        for row in 24 ..< 48 {
            try secondWindowCells.append(
                #require(
                    coordinator.tableView(
                        tableView,
                        viewFor: column,
                        row: row
                    ) as? TrackTableHostingCell
                )
            )
        }

        #expect(probe.hostingRootInstalls == 0)
        #expect(probe.hostConfigurations == 24)
        #expect(probe.hostTrackIdentityChanges == 24)
        #expect(
            Set(secondWindowCells.map { ObjectIdentifier($0.hostState) })
                == initialRootIDs
        )
        #expect(
            secondWindowCells.map(\.hostState.trackID)
                == state.rows[24 ..< 48].map { Optional($0.id) }
        )
    }

    private func reload(_ rowIndexes: IndexSet) {
        let reusable = rowIndexes.compactMap { cellsByRow[$0] }
        tableView.reusableViews.append(contentsOf: reusable)
        for row in rowIndexes {
            guard let configured = coordinator.tableView(
                tableView,
                viewFor: column,
                row: row
            ) as? TrackTableHostingCell else {
                Issue.record("Expected a reusable hosting cell at row \(row)")
                continue
            }
            cellsByRow[row] = configured
        }
    }
}

@MainActor
private final class RealAppKitUpdateState {
    var rows: [LibraryTrackProjection]
    var selection: Set<UUID>
    var version: TrackTableContentVersion

    init(
        rows: [LibraryTrackProjection],
        selection: Set<UUID>,
        version: TrackTableContentVersion
    ) {
        self.rows = rows
        self.selection = selection
        self.version = version
    }

    var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { self.selection },
            set: { self.selection = $0 }
        )
    }
}
