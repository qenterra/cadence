import Foundation

struct LibraryOperationFailure: Identifiable, Equatable, Sendable {
    enum Operation: String, Equatable, Sendable {
        case albumPage
        case artistPage
        case browserAlbums
        case browserTracks
        case catalogSearch
        case favoriteCatalog
        case playlistAdd
        case playlistCreate
        case playlistDelete
        case playlistList
        case playlistRemove
        case playlistRename
        case playlistReorder
        case playlistTracks
        case smartCollections
        case tagPage
        case trackPage
    }

    let operation: Operation
    let message: String

    var id: Operation {
        operation
    }

    var title: String {
        switch operation {
        case .albumPage:
            "Couldn’t Load Albums"
        case .artistPage:
            "Couldn’t Load Artists"
        case .browserAlbums:
            "Couldn’t Load Artist Albums"
        case .browserTracks:
            "Couldn’t Load Album Tracks"
        case .catalogSearch:
            "Search Failed"
        case .favoriteCatalog:
            "Couldn’t Load Favorites"
        case .playlistAdd:
            "Couldn’t Add to Playlist"
        case .playlistCreate:
            "Couldn’t Create Playlist"
        case .playlistDelete:
            "Couldn’t Delete Playlist"
        case .playlistList:
            "Couldn’t Load Playlists"
        case .playlistRemove:
            "Couldn’t Remove from Playlist"
        case .playlistRename:
            "Couldn’t Rename Playlist"
        case .playlistReorder:
            "Couldn’t Reorder Playlist"
        case .playlistTracks:
            "Couldn’t Load Playlist Tracks"
        case .smartCollections:
            "Smart Collection Failed"
        case .tagPage:
            "Couldn’t Load Tags"
        case .trackPage:
            "Couldn’t Load Tracks"
        }
    }

    var isRetryable: Bool {
        switch operation {
        case .playlistAdd,
             .playlistCreate,
             .playlistDelete,
             .playlistRemove,
             .playlistRename,
             .playlistReorder:
            false
        default:
            true
        }
    }
}

extension LibraryStore {
    func recordOperationFailure(
        _ operation: LibraryOperationFailure.Operation,
        error: Error
    ) {
        operationFailure = LibraryOperationFailure(
            operation: operation,
            message: error.localizedDescription
        )
    }

    func dismissOperationFailure() {
        operationFailure = nil
    }

    func retryOperationFailure() async {
        guard let failure = operationFailure else {
            return
        }
        operationFailure = nil

        switch failure.operation {
        case .albumPage, .artistPage, .tagPage:
            await loadInitialLibrary()
        case .browserAlbums:
            await browseAlbums(artistID: browserArtistID)
        case .browserTracks:
            await browseTracks(
                albumID: browserAlbumID,
                sort: browserTrackSort
            )
        case .catalogSearch:
            await searchCatalog(catalogSearchQuery)
        case .favoriteCatalog:
            await loadFavoriteCatalog()
        case .playlistList, .playlistTracks:
            await retryPlaylistLoad(failure.operation)
        case .playlistAdd,
             .playlistCreate,
             .playlistDelete,
             .playlistRemove,
             .playlistRename,
             .playlistReorder:
            break
        case .smartCollections:
            await loadSmartCollectionRuleData()
        case .trackPage:
            await replaceTracks(query: trackQuery)
        }
    }

    private func retryPlaylistLoad(
        _ operation: LibraryOperationFailure.Operation
    ) async {
        if operation == .playlistList {
            await loadPlaylists()
        } else {
            await loadSelectedPlaylistTracks()
        }
    }
}
