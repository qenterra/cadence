import SwiftUI

enum CatalogTileFavoriteLayout {
    static let controlSize: CGFloat = 22
    static let titleHorizontalInset = controlSize + 4
}

struct FavoriteControlPresentation: Equatable, Sendable {
    let visualOpacity: Double
    let acceptsPointerInteraction: Bool
    let isAccessibilityVisible: Bool

    static func resolve(
        isHovered: Bool,
        isFocused: Bool
    ) -> FavoriteControlPresentation {
        let isRevealed = isHovered || isFocused
        return FavoriteControlPresentation(
            visualOpacity: isRevealed ? 1 : 0,
            acceptsPointerInteraction: isRevealed,
            isAccessibilityVisible: true
        )
    }
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
    private(set) var feedbackTrigger = 0
    private(set) var hasFeedback = false
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
        feedbackTrigger = 0
        hasFeedback = false
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
        feedbackTrigger += 1
        hasFeedback = true
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
        if !didSave {
            feedbackTrigger += 1
            hasFeedback = true
        }
    }
}

struct FavoriteButton: View {
    let itemID: UUID
    let isFavorite: Bool
    let itemName: String
    let controlSize: CGFloat
    let action: (Bool) async -> Bool

    @State private var transientState: FavoriteButtonTransientState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        itemID: UUID,
        isFavorite: Bool,
        itemName: String,
        controlSize: CGFloat = 30,
        action: @escaping (Bool) async -> Bool
    ) {
        self.itemID = itemID
        self.isFavorite = isFavorite
        self.itemName = itemName
        self.controlSize = controlSize
        self.action = action
        _transientState = State(
            initialValue: FavoriteButtonTransientState(itemID: itemID)
        )
    }

    var body: some View {
        let motion = CadenceSymbolEffectPresentation.resolve(
            trigger: currentFeedbackTrigger,
            reduceMotion: reduceMotion || !hasCurrentFeedback
        )

        Button(action: updateFavorite) {
            favoriteSymbol(motion: motion)
                .frame(width: controlSize, height: controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(currentPendingValue != nil)
        .help(displayedValue ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(
            FavoriteButtonAccessibilityContract.label(
                isFavorite: displayedValue,
                itemName: itemName
            )
        )
        .accessibilityValue(
            FavoriteButtonAccessibilityContract.value(
                isFavorite: displayedValue
            )
        )
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

    private var currentFeedbackTrigger: Int {
        transientState.itemID == itemID
            ? transientState.feedbackTrigger
            : 0
    }

    private var hasCurrentFeedback: Bool {
        transientState.itemID == itemID
            && transientState.hasFeedback
    }

    @ViewBuilder
    private func favoriteSymbol(
        motion: CadenceSymbolEffectPresentation
    ) -> some View {
        let symbol = Image(systemName: displayedValue ? "heart.fill" : "heart")
            .foregroundStyle(
                displayedValue ? CadenceTheme.primaryAccent : .secondary
            )

        if motion.isEnabled {
            symbol
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.up, value: motion.trigger)
        } else {
            symbol
        }
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
