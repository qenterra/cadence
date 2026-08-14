import Foundation

enum ContextualMediaRoute: Hashable, Sendable {
    case artist(ArtistPreview.ID)
    case album(AlbumPreview.ID)
    case tag(TagPreview.ID)
    case productionArtist(UUID)
    case productionAlbum(UUID)
    case productionTag(UUID)
    case productionTagEditor(UUID)
}

struct ContextualNavigationSnapshot: Sendable {
    let sourceTitle: String
    let catalogSearchQuery: String
    let selectedDestination: NavigationDestination
    let selectedArtistID: ArtistPreview.ID?
    let selectedAlbumID: AlbumPreview.ID?
    let selectedTrackID: TrackPreview.ID?
    let currentTrackID: TrackPreview.ID?
    let selectedProductionArtistID: UUID?
    let selectedProductionAlbumID: UUID?
    let selectedProductionTagID: UUID?
    let selectedProductionTagEditingTrackID: UUID?

    let playbackWorkspace: PlaybackWorkspace
    let selectedNowPlayingPanel: NowPlayingPanel
    let lastNowPlayingPanel: NowPlayingPanel?

    let albumsPresentation: AlbumsPresentation
    let allAlbumsSortDescriptor: AlbumSortDescriptor
    let albumShelfSortDescriptors: [
        AlbumShelfKind: AlbumSortDescriptor
    ]
    let albumSearchQuery: String
    let albumsFocusedAlbumID: AlbumPreview.ID?

    let artistsPresentation: ArtistsPresentation
    let allArtistsSortDescriptor: ArtistSortDescriptor
    let artistShelfSortDescriptors: [
        ArtistShelfKind: ArtistSortDescriptor
    ]
    let artistSearchQuery: String
    let artistsFocusedArtistID: ArtistPreview.ID?

    let selectedTagGroupID: TagGroupID
    let selectedTagID: TagPreview.ID?
    let tagResultScope: TagResultScope
    let tagEditingSelection: TagEditingSelection
    let isTagInspectorPresented: Bool
    let isLibraryTagEditingContext: Bool

    let selectedSmartCollectionID: SmartCollectionPreview.ID?
    let smartCollectionsPresentationMode: SmartCollectionsPresentationMode
    let smartCollectionDraft: SmartCollectionDraft?
    let smartCollectionSortDescriptors: [
        SmartCollectionPreview.ID: SmartCollectionSortDescriptor
    ]
    let lastValidSmartCollectionResultIDs: [TrackPreview.ID]
}

struct ContextualNavigationEntry: Identifiable, Sendable {
    let id = UUID()
    let target: ContextualMediaRoute
    let source: ContextualNavigationSnapshot
}
