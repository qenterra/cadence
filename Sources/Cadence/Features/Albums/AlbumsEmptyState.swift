import SwiftUI

struct AlbumsEmptyState: View {
    let browseAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.title3)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("No favorite albums yet")
                    .font(.callout.weight(.semibold))
                Text("Favorite an album to keep it close.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Browse Albums", action: browseAction)
        }
        .padding(.horizontal, 14)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(CadenceTheme.subduedFill)
        )
        .accessibilityElement(children: .combine)
    }
}
