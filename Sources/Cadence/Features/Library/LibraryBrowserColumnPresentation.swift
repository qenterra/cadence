enum LibraryBrowserColumnPresentation: Equatable {
    case selectionRequired
    case loading
    case empty
    case failed(String)
    case content

    static func resolve(
        hasSelection: Bool,
        loadState: LibraryContentLoadState,
        itemCount: Int
    ) -> Self {
        guard hasSelection else {
            return .selectionRequired
        }
        switch loadState {
        case .idle, .loading:
            return .loading
        case let .failed(failure):
            return .failed(failure.message)
        case .ready:
            return itemCount == 0 ? .empty : .content
        }
    }
}
