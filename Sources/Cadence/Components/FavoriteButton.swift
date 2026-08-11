import SwiftUI

enum CatalogTileFavoriteLayout {
    static let controlSize: CGFloat = 22
    static let titleHorizontalInset = controlSize + 4
}

struct FavoriteButton: View {
    let isFavorite: Bool
    let itemName: String
    var controlSize: CGFloat = 30
    let action: (Bool) async -> Bool

    @State private var pendingValue: Bool?
    @State private var feedbackTrigger = 0

    var body: some View {
        Button(action: updateFavorite) {
            Image(systemName: displayedValue ? "heart.fill" : "heart")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(
                    displayedValue ? CadenceTheme.primaryAccent : .secondary
                )
                .symbolEffect(.bounce, value: feedbackTrigger)
                .frame(width: controlSize, height: controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .disabled(pendingValue != nil)
        .help(displayedValue ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(
            displayedValue
                ? "Remove \(itemName) from Favorites"
                : "Add \(itemName) to Favorites"
        )
        .accessibilityValue(displayedValue ? "Favorite" : "Not Favorite")
    }

    private var displayedValue: Bool {
        pendingValue ?? isFavorite
    }

    private func updateFavorite() {
        guard pendingValue == nil else {
            return
        }
        let requestedValue = !isFavorite
        pendingValue = requestedValue
        feedbackTrigger += 1

        Task { @MainActor in
            let didSave = await action(requestedValue)
            await Task.yield()
            pendingValue = nil
            if !didSave {
                feedbackTrigger += 1
            }
        }
    }
}
