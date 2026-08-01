import Foundation

struct LibraryOperationFailure: Identifiable, Equatable, Sendable {
    enum Operation: String, Equatable, Sendable {
        case albumPage
        case artistPage
        case browserAlbums
        case browserTracks
        case catalogSearch
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
        case .smartCollections:
            "Smart Collection Failed"
        case .tagPage:
            "Couldn’t Load Tags"
        case .trackPage:
            "Couldn’t Load Tracks"
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
}
