import QenTerraMediaComponents
import SwiftUI

enum CatalogTileFavoriteLayout {
    static let controlSize: CGFloat = 22
    static let titleHorizontalInset = controlSize + 4
}

enum FavoriteButtonAccessibilityContract {
    static func label(isFavorite: Bool, itemName: String) -> String {
        isFavorite
            ? "Remove \(itemName) from Favorites"
            : "Add \(itemName) to Favorites"
    }

    static func value(isFavorite: Bool) -> String {
        isFavorite ? "Favorite" : "Not Favorite"
    }
}

struct FavoriteButtonRequest: Equatable, Sendable {
    let itemID: UUID
    let token: UUID
    let requestedValue: Bool
}

struct FavoriteButtonTransientState: Equatable, Sendable {
    private(set) var itemID: UUID
    private(set) var pendingValue: Bool?
    private(set) var activeRequestToken: UUID?

    init(itemID: UUID) {
        self.itemID = itemID
    }

    mutating func reconcile(itemID: UUID) {
        guard self.itemID != itemID else {
            return
        }
        self.itemID = itemID
        pendingValue = nil
        activeRequestToken = nil
    }

    mutating func begin(isFavorite: Bool) -> FavoriteButtonRequest? {
        guard pendingValue == nil else {
            return nil
        }
        let request = FavoriteButtonRequest(
            itemID: itemID,
            token: UUID(),
            requestedValue: !isFavorite
        )
        pendingValue = request.requestedValue
        activeRequestToken = request.token
        return request
    }

    mutating func complete(
        _ request: FavoriteButtonRequest,
        didSave: Bool
    ) {
        guard itemID == request.itemID,
              activeRequestToken == request.token else {
            return
        }
        pendingValue = nil
        activeRequestToken = nil
        _ = didSave
    }
}

struct FavoriteButton: View {
    let itemID: UUID
    let isFavorite: Bool
    let itemName: String
    let controlSize: CGFloat
    let isRevealed: Bool
    let interactionContext: MediaAccessoryInteractionContext
    let action: (Bool) async -> Bool

    @State private var transientState: FavoriteButtonTransientState

    init(
        itemID: UUID,
        isFavorite: Bool,
        itemName: String,
        controlSize: CGFloat = 30,
        isRevealed: Bool = true,
        interactionContext: MediaAccessoryInteractionContext = .init(),
        action: @escaping (Bool) async -> Bool
    ) {
        self.itemID = itemID
        self.isFavorite = isFavorite
        self.itemName = itemName
        self.controlSize = controlSize
        self.isRevealed = isRevealed
        self.interactionContext = interactionContext
        self.action = action
        _transientState = State(
            initialValue: FavoriteButtonTransientState(itemID: itemID)
        )
    }

    var body: some View {
        FavoriteControl(
            presentation: FavoritePresentation(
                isFavorite: displayedValue,
                isPending: currentPendingValue != nil,
                isRevealed: isRevealed,
                accessibilityLabel: FavoriteButtonAccessibilityContract.label(
                    isFavorite: displayedValue,
                    itemName: itemName
                ),
                accessibilityValue: FavoriteButtonAccessibilityContract.value(
                    isFavorite: displayedValue
                )
            ),
            interactionContext: interactionContext,
            controlSize: controlSize
        ) { _ in
            updateFavorite()
        }
        .tint(CadenceTheme.primaryAccent)
        .onChange(of: itemID) {
            transientState.reconcile(itemID: itemID)
        }
    }

    private var displayedValue: Bool {
        currentPendingValue ?? isFavorite
    }

    private var currentPendingValue: Bool? {
        transientState.itemID == itemID
            ? transientState.pendingValue
            : nil
    }

    private func updateFavorite() {
        transientState.reconcile(itemID: itemID)
        guard let request = transientState.begin(isFavorite: isFavorite) else {
            return
        }

        Task { @MainActor in
            let didSave = await action(request.requestedValue)
            await Task.yield()
            transientState.complete(request, didSave: didSave)
        }
    }
}
