import SwiftUI

struct FavoriteButton: View {
    let isFavorite: Bool
    let itemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(
                    isFavorite ? CadenceTheme.primaryAccent : .secondary
                )
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(
            isFavorite
                ? "Remove \(itemName) from Favorites"
                : "Add \(itemName) to Favorites"
        )
    }
}
