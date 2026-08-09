import Foundation
import Observation

struct ImportWorkspaceState {
    var autoAdvanceEnabled = true
    var scanError: String?
    var operationError: String?
    var progress: ManagedImportProgress?
    var completion: ManagedImportCompletion?
    let initialCandidates: [ImportCandidatePreview]
}

struct LibraryRelocationWorkspaceState {
    var progress: LibraryRelocationProgress?
    var error: String?
    var pendingConflictParent: URL?
    var isMoving = false
}

struct PendingLibraryDeletion: Equatable, Sendable {
    let kind: TrashTargetKind
    let ids: [UUID]
    let title: String

    init(
        kind: TrashTargetKind,
        id: UUID,
        title: String
    ) {
        self.kind = kind
        ids = [id]
        self.title = title
    }

    init(
        kind: TrashTargetKind,
        ids: [UUID],
        title: String
    ) {
        self.kind = kind
        self.ids = ids
        self.title = title
    }

    var id: UUID? {
        ids.first
    }
}

@MainActor
@Observable
final class CadenceAppModel {
    let librarySession: LibrarySession
    let tracks: [TrackPreview]
    private(set) var tags: [TagPreview]
    private(set) var tagAssignments: Set<TagAssignmentPreview>
    private(set) var tagExclusions: Set<TagExclusionPreview>
    private(set) var dismissedTagSuggestions: Set<TagSuggestionDismissal> = []
    var smartCollections: [SmartCollectionPreview]
    var lyricDocuments: [TrackPreview.ID: LyricDocument]

    var selectedDestination: NavigationDestination = .library
    var selectedArtistID: ArtistPreview.ID?
    var selectedAlbumID: AlbumPreview.ID?
    var selectedTrackID: TrackPreview.ID?
    var selectedProductionArtistID: UUID?
    var selectedProductionAlbumID: UUID?
    var selectedProductionTagID: UUID?
    var selectedProductionTagEditingTrackID: UUID?
    var selectedTagGroupID: TagGroupID = .all
    var selectedTagID: TagPreview.ID?
    var tagResultScope: TagResultScope = .tracks
    var tagEditingSelection = TagEditingSelection()
    var isTagInspectorPresented = false
    var isLibraryTagEditingContext = false
    var currentTrackID: TrackPreview.ID?
    var searchQuery = ""
    var searchScope: LibrarySearchScope = .currentAlbum
    var previewIsPlaying = false
    var previewIsShuffleEnabled = false
    var previewRepeatMode: RepeatMode = .off
    var previewProgress = 0.32
    var previewVolume = 0.72
    var activePlaybackQueue: PlaybackQueue?
    var selectedSmartCollectionID: SmartCollectionPreview.ID?
    var smartCollectionDraft: SmartCollectionDraft?
    var smartCollectionsPresentationMode: SmartCollectionsPresentationMode = .listening
    var smartCollectionSortDescriptors: [
        SmartCollectionPreview.ID: SmartCollectionSortDescriptor
    ] = [:]
    var lastValidSmartCollectionResultIDs: [TrackPreview.ID] = []
    var pendingSmartCollectionTransition: SmartCollectionTransitionTarget?
    var pendingSmartCollectionDeletionID: SmartCollectionPreview.ID?
    var smartCollectionNameFocusRequest: UUID?
    var previousSavedSmartCollectionID: SmartCollectionPreview.ID?
    var playbackWorkspace: PlaybackWorkspace = .hidden
    var selectedNowPlayingPanel: NowPlayingPanel = .lyrics
    var lastNowPlayingPanel: NowPlayingPanel?
    var lyricDraft: LyricDraft?
    var pendingLyricsTransition: LyricsTransitionTarget?
    var isLoadingLyricDraft = false
    var isSavingLyricDraft = false
    var lyricPersistenceError: String?
    var lyricsRevision = 0
    var lyricLoadRequestID: UUID?
    var lyricsSearchTarget: LyricsCatalogSearchResult?
    var albumsPresentation: AlbumsPresentation = .overview
    var allAlbumsSortDescriptor: AlbumSortDescriptor = .allAlbums
    var albumShelfSortDescriptors: [AlbumShelfKind: AlbumSortDescriptor] = [:]
    var albumSearchQuery = ""
    var albumsOverviewScrollAnchor: AlbumBrowseAnchor?
    var albumGridScrollAnchors: [AlbumShelfKind: AlbumBrowseAnchor] = [:]
    var albumsFocusedAlbumID: AlbumPreview.ID?
    var favoriteAlbumDates: [AlbumPreview.ID: Date]
    var artistsPresentation: ArtistsPresentation = .overview
    var allArtistsSortDescriptor: ArtistSortDescriptor = .allArtists
    var artistShelfSortDescriptors: [ArtistShelfKind: ArtistSortDescriptor] = [:]
    var artistSearchQuery = ""
    var artistsOverviewScrollAnchor: ArtistBrowseAnchor?
    var artistGridScrollAnchors: [ArtistShelfKind: ArtistBrowseAnchor] = [:]
    var artistsFocusedArtistID: ArtistPreview.ID?
    var favoriteArtistDates: [ArtistPreview.ID: Date]
    let artworkRepository: any ArtworkRepository
    var artworkRevision = 0
    var pendingArtworkImportTarget: ArtworkTarget?
    var isArtworkImporterPresented = false
    var artworkCropDraft: ArtworkCropDraft?
    var artworkImportError: String?
    var contextualNavigationHistory: [ContextualNavigationEntry] = []
    var importPreviewStage: ImportPreviewStage = .empty
    var importReviewCategory: ImportReviewCategory = .ready
    var importCandidates: [ImportCandidatePreview]
    var includedImportCandidateIDs: Set<ImportCandidatePreview.ID> = []
    var selectedImportCandidateIDs: Set<ImportCandidatePreview.ID> = []
    var importSelectionAnchorID: ImportCandidatePreview.ID?
    var isImportDropTargeted = false
    var importScanProgress: ImportInspectionProgress = .empty
    var importWorkspaceState: ImportWorkspaceState
    var pendingLibraryDeletion: PendingLibraryDeletion?
    var libraryOperationError: String?
    var libraryRelocationState = LibraryRelocationWorkspaceState()

    private(set) var favoriteTrackIDs: Set<TrackPreview.ID>
    var importCoordinator: ImportCoordinator?
    var importDestination: ManagedLibraryImportDestination?
    var importRecovery: ManagedLibraryImportRecovery?
    let playbackCoordinator: PlaybackCoordinator?
    let libraryRelocator: LibraryRelocator

    init(
        librarySession: LibrarySession,
        tracks: [TrackPreview],
        tags: [TagPreview],
        tagAssignments: Set<TagAssignmentPreview>,
        tagExclusions: Set<TagExclusionPreview>,
        smartCollections: [SmartCollectionPreview],
        lyricDocuments: [TrackPreview.ID: LyricDocument],
        favoriteAlbumDates: [AlbumPreview.ID: Date],
        favoriteArtistDates: [ArtistPreview.ID: Date],
        importCandidates: [ImportCandidatePreview],
        importCoordinator: ImportCoordinator? = nil,
        importDestination: ManagedLibraryImportDestination? = nil,
        importRecovery: ManagedLibraryImportRecovery? = nil,
        playbackCoordinator: PlaybackCoordinator? = nil,
        libraryRelocator: LibraryRelocator = LibraryRelocator(),
        artworkRepository: any ArtworkRepository = InMemoryArtworkRepository()
    ) {
        self.librarySession = librarySession
        self.tracks = tracks
        self.tags = tags
        self.tagAssignments = tagAssignments
        self.tagExclusions = tagExclusions
        self.smartCollections = smartCollections
        self.lyricDocuments = lyricDocuments
        self.favoriteAlbumDates = favoriteAlbumDates
        self.favoriteArtistDates = favoriteArtistDates
        self.importCandidates = importCandidates
        importWorkspaceState = ImportWorkspaceState(
            initialCandidates: importCandidates
        )
        self.importCoordinator = importCoordinator
        self.importDestination = importDestination
        self.importRecovery = importRecovery
        self.playbackCoordinator = playbackCoordinator
        self.libraryRelocator = libraryRelocator
        self.artworkRepository = artworkRepository
        selectedArtistID = tracks.first?.artistID
        selectedAlbumID = tracks.first?.albumID
        selectedTrackID = tracks.first?.id
        let orderedTags = tags.sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
        selectedTagID = orderedTags.first { $0.id == "genre/ambient" }?.id
            ?? orderedTags.first?.id
        currentTrackID = tracks.first?.id
        favoriteTrackIDs = Set(tracks.filter(\.isFavorite).map(\.id))
        prepareInitialSmartCollection()
        resetImportPreviewCandidates()
        importCoordinator?.onStateChange = { [weak self] state in
            self?.applyImportCoordinatorState(state)
        }
    }
}

extension CadenceAppModel {
    var artists: [ArtistPreview] {
        Dictionary(grouping: tracks, by: \.artistID)
            .map { artistID, artistTracks in
                ArtistPreview(
                    id: artistID,
                    name: artistTracks.first?.artist ?? artistID,
                    albumCount: Set(artistTracks.map(\.albumID)).count,
                    trackCount: artistTracks.count
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedArtist: ArtistPreview? {
        artists.first { $0.id == selectedArtistID }
    }

    var albums: [AlbumPreview] {
        Dictionary(grouping: tracks, by: \.albumID)
            .map { albumID, albumTracks in
                let firstTrack = albumTracks.first
                let genres = Set(
                    albumTracks.flatMap { track in
                        effectiveTags(for: track)
                            .filter { $0.groupID == .hierarchy("genre") }
                            .map(\.displayName)
                    }
                )
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

                return AlbumPreview(
                    id: albumID,
                    title: firstTrack?.album ?? albumID,
                    artist: firstTrack?.artist ?? "Unknown Artist",
                    year: firstTrack?.year ?? 0,
                    dateAdded: albumTracks.map(\.dateAdded).min() ?? .distantPast,
                    trackCount: albumTracks.count,
                    totalDuration: albumTracks.reduce(0) { $0 + $1.duration },
                    artworkPalette: albumTracks.compactMap(\.artworkPalette).first,
                    genres: Array(genres.prefix(2))
                )
            }
            .sorted(by: albumComesBefore)
    }

    var albumsForSelectedArtist: [AlbumPreview] {
        guard let selectedArtistID else {
            return []
        }
        return albums(for: selectedArtistID)
    }

    var selectedAlbum: AlbumPreview? {
        albumsForSelectedArtist.first { $0.id == selectedAlbumID }
    }

    var selectedAlbumTracks: [TrackPreview] {
        AlbumListeningProjection.canonicalTracks(
            tracks.filter { $0.albumID == selectedAlbumID }
        )
    }

    var visibleTracks: [TrackPreview] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return selectedAlbumTracks
        }

        let source = searchScope == .library ? tracks : selectedAlbumTracks
        return source.filter { track in
            track.title.localizedStandardContains(query)
                || track.artist.localizedStandardContains(query)
                || track.album.localizedStandardContains(query)
                || effectiveTags(for: track).contains {
                    $0.id.localizedStandardContains(query)
                }
        }
    }

    var isShowingLibrarySearchResults: Bool {
        searchScope == .library
            && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedTrack: TrackPreview? {
        tracks.first { $0.id == selectedTrackID }
    }

    var currentTrack: TrackPreview? {
        tracks.first { $0.id == currentTrackID }
    }

    func isFavorite(_ track: TrackPreview) -> Bool {
        favoriteTrackIDs.contains(track.id)
    }

    func toggleFavorite(_ track: TrackPreview) {
        if favoriteTrackIDs.contains(track.id) {
            favoriteTrackIDs.remove(track.id)
        } else {
            favoriteTrackIDs.insert(track.id)
        }
    }

    func selectArtist(_ artist: ArtistPreview) {
        selectedArtistID = artist.id
        let firstAlbum = albums(for: artist.id).first
        selectedAlbumID = firstAlbum?.id
        selectedTrackID = tracks.first { $0.albumID == firstAlbum?.id }?.id
    }

    func selectAlbum(_ album: AlbumPreview) {
        selectedArtistID = album.artist
        selectedAlbumID = album.id
        selectedTrackID = tracks.first { $0.albumID == album.id }?.id
    }

    func selectTrack(_ track: TrackPreview) {
        selectedArtistID = track.artistID
        selectedAlbumID = track.albumID
        selectedTrackID = track.id
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    private func albums(for artistID: ArtistPreview.ID) -> [AlbumPreview] {
        albums.filter { $0.artist == artistID }
    }

    private func albumComesBefore(
        _ lhs: AlbumPreview,
        _ rhs: AlbumPreview
    ) -> Bool {
        let artistOrder = lhs.artist.localizedStandardCompare(rhs.artist)
        if artistOrder != .orderedSame {
            return artistOrder == .orderedAscending
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

extension CadenceAppModel {
    func replaceTagEditingState(
        tags: [TagPreview],
        assignments: Set<TagAssignmentPreview>,
        exclusions: Set<TagExclusionPreview>,
        dismissals: Set<TagSuggestionDismissal>
    ) {
        self.tags = tags
        tagAssignments = assignments
        tagExclusions = exclusions
        dismissedTagSuggestions = dismissals
    }

    @discardableResult
    func insertTagForEditing(_ tag: TagPreview) -> Bool {
        guard !tags.contains(where: { $0.id == tag.id }) else {
            return false
        }
        tags.append(tag)
        return true
    }

    @discardableResult
    func insertTagAssignmentsForEditing(
        _ assignments: [TagAssignmentPreview]
    ) -> Bool {
        let originalCount = tagAssignments.count
        tagAssignments.formUnion(assignments)
        return tagAssignments.count != originalCount
    }

    @discardableResult
    func removeTagAssignmentsForEditing(
        _ assignments: [TagAssignmentPreview]
    ) -> Bool {
        let originalCount = tagAssignments.count
        tagAssignments.subtract(assignments)
        return tagAssignments.count != originalCount
    }

    @discardableResult
    func insertTagExclusionsForEditing(
        _ exclusions: [TagExclusionPreview]
    ) -> Bool {
        let originalCount = tagExclusions.count
        tagExclusions.formUnion(exclusions)
        return tagExclusions.count != originalCount
    }

    @discardableResult
    func removeTagExclusionsForEditing(
        _ exclusions: [TagExclusionPreview]
    ) -> Bool {
        let originalCount = tagExclusions.count
        tagExclusions.subtract(exclusions)
        return tagExclusions.count != originalCount
    }

    @discardableResult
    func insertTagDismissalsForEditing(
        _ dismissals: [TagSuggestionDismissal]
    ) -> Bool {
        let originalCount = dismissedTagSuggestions.count
        dismissedTagSuggestions.formUnion(dismissals)
        return dismissedTagSuggestions.count != originalCount
    }
}
