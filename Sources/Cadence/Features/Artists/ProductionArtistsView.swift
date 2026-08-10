import SwiftUI

struct ProductionArtistsView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @AppStorage("artists.sortField") private var sortFieldRaw = ArtistSortField.name.rawValue
    @AppStorage("artists.sortDescending") private var sortsDescending = false

    var body: some View {
        Group {
            if let artistID = model.selectedProductionArtistID {
                ProductionArtistDetailView(
                    model: model,
                    store: store,
                    artistID: artistID
                )
            } else if store.artists.isEmpty {
                emptyContent
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            header

                            LazyVGrid(
                                columns: columns(for: geometry.size.width),
                                alignment: .leading,
                                spacing: 28
                            ) {
                                ForEach(sortedArtists) { artist in
                                    artistTile(artist)
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                    }
                }
            }
        }
        .background(CadenceTheme.contentBackground)
    }

    @ViewBuilder
    private var emptyContent: some View {
        if store.availability == .loading {
            ProgressView("Loading Artists")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyLibraryView(
                title: "No Artists Yet",
                description: "Artists will appear here after you import music."
            ) {
                model.requestNavigationDestination(.importMusic)
            }
        }
    }

    private var header: some View {
        CadencePageHeader(
            "Artists",
            subtitle: "\(store.artists.count) artists"
        ) {
            Menu {
                Picker("Sort Artists", selection: $sortFieldRaw) {
                    ForEach(artistSortFields) { field in
                        Text(field.title).tag(field.rawValue)
                    }
                }
                Toggle("Descending", isOn: $sortsDescending)
            } label: {
                Label("Sort Artists", systemImage: "arrow.up.arrow.down.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var sortedArtists: [LibraryArtistProjection] {
        let field = ArtistSortField(rawValue: sortFieldRaw) ?? .name
        return store.artists.sorted(by: { lhs, rhs in
            let comparison: ComparisonResult = switch field {
            case .name:
                lhs.name.localizedStandardCompare(rhs.name)
            case .recentlyPlayed:
                lhs.name.localizedStandardCompare(rhs.name)
            case .albumCount:
                comparison(of: lhs.albumCount, and: rhs.albumCount)
            case .trackCount:
                comparison(of: lhs.trackCount, and: rhs.trackCount)
            case .favoriteDate:
                (lhs.favoriteDate ?? .distantPast).compare(
                    rhs.favoriteDate ?? .distantPast
                )
            }
            return sortsDescending
                ? comparison == .orderedDescending
                : comparison == .orderedAscending
        })
    }

    private var artistSortFields: [ArtistSortField] {
        ArtistSortField.allCases.filter { $0 != .recentlyPlayed }
    }

    private func comparison(of lhs: Int, and rhs: Int) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private func artistTile(
        _ artist: LibraryArtistProjection
    ) -> some View {
        ProductionArtistTile(
            model: model,
            store: store,
            artist: artist
        )
    }

    private func columns(
        for width: CGFloat
    ) -> [GridItem] {
        let contentWidth = max(width - 56, 600)
        let count = max(Int(contentWidth / 190), 3)
        return Array(
            repeating: GridItem(.flexible(), spacing: 18),
            count: count
        )
    }
}

private struct ProductionArtistTile: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    let artist: LibraryArtistProjection
    @State private var isHovered = false

    var body: some View {
        Button {
            model.requestOpenProductionArtistContextually(id: artist.id)
        } label: {
            VStack(alignment: .center, spacing: 10) {
                ProductionArtworkView(
                    model: model,
                    artworkID: artist.customArtworkID,
                    title: artist.name,
                    placeholder: .artist,
                    cornerRadius: CadenceTheme.radiusNone,
                    showsBorder: false
                )
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
                }

                Text(artist.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    "\(artist.albumCount) albums · "
                        + "\(artist.trackCount) tracks"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(10)
            .background {
                BrowserRowSurface(
                    isSelected: false,
                    isHovered: isHovered,
                    isFocused: false
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .onHover { isHovered = $0 }
        .contextMenu {
            artistActions
        }
        .task {
            if artist.id == store.artists.last?.id {
                await store.loadNextArtists()
            }
        }
    }

    @ViewBuilder
    private var artistActions: some View {
        AddArtistToPlaylistMenuItems(
            store: store,
            artistID: artist.id
        )
        ArtworkMenuItems(
            model: model,
            target: .managedArtist(artist.id),
            label: "Artist Image"
        )
        Button(
            "Move Artist to Trash…",
            systemImage: "trash",
            role: .destructive
        ) {
            model.requestLibraryDeletion(
                kind: .artist,
                id: artist.id,
                title: artist.name
            )
        }
    }
}
