import Foundation
import Observation

enum CadenceRuntimeMode: Equatable, Sendable {
    case production
    case preview
}

extension CadenceAppModel {
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

enum ImportRuntimeAvailability: Equatable, Sendable {
    case available
    case preview
    case unavailable(String)
}

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
    let runtimeEnvironment: CadenceRuntimeEnvironment
    let importRuntimeAvailability: ImportRuntimeAvailability
    let librarySession: LibrarySession
    let tracks: [TrackPreview]
    private(set) var tags: [TagPreview]
    private(set) var tagAssignments: Set<TagAssignmentPreview>
    private(set) var tagExclusions: Set<TagExclusionPreview>
    private(set) var dismissedTagSuggestions: Set<TagSuggestionDismissal> = []
    var smartCollections: [SmartCollectionPreview]
    var lyricDocuments: [TrackPreview.ID: LyricDocument]

    var selectedDestination: NavigationDestination = .home
    var selectedArtistID: ArtistPreview.ID?
    var selectedAlbumID: AlbumPreview.ID?
    var selectedTrackID: TrackPreview.ID?
    var selectedProductionArtistID: UUID?
    var selectedProductionAlbumID: UUID?
    var selectedProductionTagID: UUID?
    var selectedProductionTagEditingTrackID: UUID?
    var catalogActivationSelection = CatalogActivationSelection()
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
    var mutedVolume: Double?
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
    var albumsFocusedAlbumID: AlbumPreview.ID?
    var favoriteAlbumDates: [AlbumPreview.ID: Date]
    var artistsPresentation: ArtistsPresentation = .overview
    var allArtistsSortDescriptor: ArtistSortDescriptor = .allArtists
    var artistShelfSortDescriptors: [ArtistShelfKind: ArtistSortDescriptor] = [:]
    var artistSearchQuery = ""
    var artistsFocusedArtistID: ArtistPreview.ID?
    var favoriteArtistDates: [ArtistPreview.ID: Date]
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
    var isResettingLibrary = false
    var libraryResetNotice: String?
    var libraryResetRevision = 0
    var externalAudioNotice: String?
    var externalAudioOpenError: String?

    private(set) var favoriteTrackIDs: Set<TrackPreview.ID>
    var importCoordinator: ImportCoordinator?
    var importDestination: ManagedLibraryImportDestination?
    var importRecovery: ManagedLibraryImportRecovery?
    let playbackCoordinator: PlaybackCoordinator?
    let externalAudioSession: ExternalAudioSession?
    let libraryRelocator: LibraryRelocator
    let libraryResetter: ManagedLibraryResetter
    let remoteLibraryController: RemoteLibraryController?

    var runtimeMode: CadenceRuntimeMode {
        runtimeEnvironment.mode
    }

    init(
        runtimeEnvironment: CadenceRuntimeEnvironment,
        importRuntimeAvailability: ImportRuntimeAvailability,
        librarySession: LibrarySession,
        importCoordinator: ImportCoordinator? = nil,
        importDestination: ManagedLibraryImportDestination? = nil,
        importRecovery: ManagedLibraryImportRecovery? = nil,
        playbackCoordinator: PlaybackCoordinator? = nil,
        externalAudioSession: ExternalAudioSession? = nil,
        remoteLibraryController: RemoteLibraryController? = nil,
        libraryRelocator: LibraryRelocator = LibraryRelocator(),
        libraryResetter: ManagedLibraryResetter = ManagedLibraryResetter()
    ) {
        let fixture = runtimeEnvironment.previewFixture
        let initialTracks = fixture?.tracks ?? []
        let initialTags = fixture?.tags ?? []
        let initialImportCandidates = fixture?.importCandidates ?? []
        self.runtimeEnvironment = runtimeEnvironment
        self.importRuntimeAvailability = importRuntimeAvailability
        self.librarySession = librarySession
        tracks = initialTracks
        tags = initialTags
        tagAssignments = fixture?.tagAssignments ?? []
        tagExclusions = fixture?.tagExclusions ?? []
        smartCollections = fixture?.smartCollections ?? []
        lyricDocuments = fixture?.lyricDocuments ?? [:]
        favoriteAlbumDates = fixture?.favoriteAlbumDates ?? [:]
        favoriteArtistDates = fixture?.favoriteArtistDates ?? [:]
        importCandidates = initialImportCandidates
        importWorkspaceState = ImportWorkspaceState(
            initialCandidates: initialImportCandidates
        )
        self.importCoordinator = importCoordinator
        self.importDestination = importDestination
        self.importRecovery = importRecovery
        self.playbackCoordinator = playbackCoordinator
        self.externalAudioSession = externalAudioSession
        self.remoteLibraryController = remoteLibraryController
        self.libraryRelocator = libraryRelocator
        self.libraryResetter = libraryResetter
        selectedArtistID = initialTracks.first?.artistID
        selectedAlbumID = initialTracks.first?.albumID
        selectedTrackID = initialTracks.first?.id
        let orderedTags = initialTags.sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
        selectedTagID = orderedTags.first { $0.id == "genre/ambient" }?.id
            ?? orderedTags.first?.id
        currentTrackID = initialTracks.first?.id
        favoriteTrackIDs = Set(initialTracks.filter(\.isFavorite).map(\.id))
        prepareInitialSmartCollection()
        resetImportPreviewCandidates()
        importCoordinator?.onStateChange = { [weak self] state in
            self?.applyImportCoordinatorState(state)
        }
    }
}

enum CatalogActivationKind: Hashable, Sendable {
    case track
    case album
    case artist
    case playlist
    case smartCollection
    case tag
}

struct CatalogActivationTarget: Hashable, Sendable {
    let kind: CatalogActivationKind
    let id: UUID
}

struct CatalogActivationSelection: Equatable, Sendable {
    private(set) var selected: CatalogActivationTarget?

    mutating func request(_ target: CatalogActivationTarget) -> Bool {
        guard selected == target else {
            selected = target
            return false
        }
        return true
    }
}

extension CadenceAppModel {
    func requestCatalogActivation(
        _ target: CatalogActivationTarget
    ) -> Bool {
        catalogActivationSelection.request(target)
    }
}
