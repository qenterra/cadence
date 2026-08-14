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
            String(localized: "Couldn’t Load Albums")
        case .artistPage:
            String(localized: "Couldn’t Load Artists")
        case .browserAlbums:
            String(localized: "Couldn’t Load Artist Albums")
        case .browserTracks:
            String(localized: "Couldn’t Load Album Tracks")
        case .catalogSearch:
            String(localized: "Couldn’t Search Library")
        case .favoriteCatalog:
            String(localized: "Couldn’t Load Favorites")
        case .playlistAdd:
            String(localized: "Couldn’t Add to Playlist")
        case .playlistCreate:
            String(localized: "Couldn’t Create Playlist")
        case .playlistDelete:
            String(localized: "Couldn’t Delete Playlist")
        case .playlistList:
            String(localized: "Couldn’t Load Playlists")
        case .playlistRemove:
            String(localized: "Couldn’t Remove from Playlist")
        case .playlistRename:
            String(localized: "Couldn’t Rename Playlist")
        case .playlistReorder:
            String(localized: "Couldn’t Reorder Playlist")
        case .playlistTracks:
            String(localized: "Couldn’t Load Playlist Tracks")
        case .smartCollections:
            String(localized: "Couldn’t Load Smart Collections")
        case .tagPage:
            String(localized: "Couldn’t Load Tags")
        case .trackPage:
            String(localized: "Couldn’t Load Tracks")
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
