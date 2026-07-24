import Foundation
import Observation

@MainActor
@Observable
final class CadenceAppModel {
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
    var selectedTagGroupID: TagGroupID = .all
    var selectedTagID: TagPreview.ID?
    var tagResultScope: TagResultScope = .tracks
    var tagEditingSelection = TagEditingSelection()
    var isTagInspectorPresented = false
    var isLibraryTagEditingContext = false
    var currentTrackID: TrackPreview.ID?
    var searchQuery = ""
    var searchScope: LibrarySearchScope = .currentAlbum
    var isPlaying = false
    var isShuffleEnabled = false
    var repeatMode: RepeatMode = .off
    var progress = 0.32
    var volume = 0.72
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
    var albumsPresentation: AlbumsPresentation = .overview
    var allAlbumsSortDescriptor: AlbumSortDescriptor = .allAlbums
    var albumShelfSortDescriptors: [AlbumShelfKind: AlbumSortDescriptor] = [:]
    var albumSearchQuery = ""
    var albumsOverviewScrollAnchor: AlbumBrowseAnchor?
    var albumGridScrollAnchors: [AlbumShelfKind: AlbumBrowseAnchor] = [:]
    var albumsFocusedAlbumID: AlbumPreview.ID?
    var favoriteAlbumDates: [AlbumPreview.ID: Date]

    private(set) var favoriteTrackIDs: Set<TrackPreview.ID>

    init(
        tracks: [TrackPreview] = .mockLibrary,
        tags: [TagPreview] = .mockTags,
        tagAssignments: Set<TagAssignmentPreview> = .mockTagAssignments,
        tagExclusions: Set<TagExclusionPreview> = .mockTagExclusions,
        smartCollections: [SmartCollectionPreview] = .mockSmartCollections,
        lyricDocuments: [TrackPreview.ID: LyricDocument] = .mockLyrics,
        favoriteAlbumDates: [AlbumPreview.ID: Date] = .mockAlbumFavorites
    ) {
        self.tracks = tracks
        self.tags = tags
        self.tagAssignments = tagAssignments
        self.tagExclusions = tagExclusions
        self.smartCollections = smartCollections
        self.lyricDocuments = lyricDocuments
        self.favoriteAlbumDates = favoriteAlbumDates
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
    }

    var artists: [ArtistPreview] {
        Dictionary(grouping: tracks, by: \.artistID)
            .map { artistID, artistTracks in
                ArtistPreview(
                    id: artistID,
                    name: artistTracks.first?.artist ?? artistID,
                    albumCount: Set(artistTracks.map(\.albumID)).count,
                    trackCount: artistTracks.count,
                    artworkPalette: artistTracks.first?.artworkPalette ?? .silver
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
                    artworkPalette: firstTrack?.artworkPalette ?? .silver,
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

enum NavigationDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case library
    case albums
    case artists
    case tags
    case graph
    case smartCollections
    case importFolder
    case settings

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .library: "Library"
        case .albums: "Albums"
        case .artists: "Artists"
        case .tags: "Tags"
        case .graph: "Graph"
        case .smartCollections: "Smart Collections"
        case .importFolder: "Import Folder"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .library: "music.note.list"
        case .albums: "square.stack"
        case .artists: "person.2"
        case .tags: "tag"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .smartCollections: "sparkles.rectangle.stack"
        case .importFolder: "folder.badge.plus"
        case .settings: "gearshape"
        }
    }
}

enum RepeatMode: String {
    case off
    case all
    case one

    var next: Self {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var symbolName: String {
        self == .one ? "repeat.1" : "repeat"
    }
}

enum LibrarySearchScope: String, CaseIterable, Identifiable {
    case currentAlbum
    case library

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .currentAlbum: "Album"
        case .library: "Library"
        }
    }
}
