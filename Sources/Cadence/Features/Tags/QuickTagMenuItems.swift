import SwiftUI

struct QuickTrackTagMenuItems: View {
    @Bindable var store: LibraryStore
    let trackIDs: [UUID]

    var body: some View {
        Menu("Add Tag", systemImage: "tag.badge.plus") {
            if store.tags.isEmpty {
                Text("No Tags Yet")
            } else {
                ForEach(store.tags) { tag in
                    Button(tag.displayPath) {
                        Task {
                            try? await store.assignTag(
                                tag.id,
                                trackIDs: trackIDs
                            )
                        }
                    }
                }
            }
        }
    }
}

struct QuickAlbumTagMenuItems: View {
    @Bindable var store: LibraryStore
    let albumID: UUID

    var body: some View {
        Menu("Add Tag", systemImage: "tag.badge.plus") {
            if store.tags.isEmpty {
                Text("No Tags Yet")
            } else {
                ForEach(store.tags) { tag in
                    Button(tag.displayPath) {
                        Task {
                            try? await store.assignTag(
                                tag.id,
                                albumID: albumID
                            )
                        }
                    }
                }
            }
        }
    }
}
