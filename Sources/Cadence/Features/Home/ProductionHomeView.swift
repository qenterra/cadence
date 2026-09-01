import SwiftUI

enum HomeContentSection: String, Hashable, Identifiable, Sendable {
    case recentlyPlayed
    case pinned
    case favorites

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .recentlyPlayed: String(localized: "Recently Played")
        case .pinned: String(localized: "Pinned")
        case .favorites: String(localized: "Favorites")
        }
    }

    var symbolName: String {
        switch self {
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .pinned: "pin"
        case .favorites: "heart"
        }
    }

    static let personalizedOrder: [HomeContentSection] = [
        .recentlyPlayed,
        .pinned,
        .favorites,
    ]
}

enum HomeSectionConfiguration {
    static let configurableSections: [HomeContentSection] = [
        .pinned,
        .favorites,
    ]

    static var defaultOrderRawValue: String {
        encode(configurableSections)
    }

    static func orderedConfigurableSections(
        from rawValue: String
    ) -> [HomeContentSection] {
        let allowed = Set(configurableSections)
        let decoded = rawValue
            .split(separator: ",")
            .compactMap { HomeContentSection(rawValue: String($0)) }
            .filter(allowed.contains)
        var seen = Set<HomeContentSection>()
        let unique = decoded.filter { seen.insert($0).inserted }
        return unique + configurableSections.filter { !seen.contains($0) }
    }

    static func hiddenSections(
        from rawValue: String
    ) -> Set<HomeContentSection> {
        let allowed = Set(configurableSections)
        return Set(
            rawValue
                .split(separator: ",")
                .compactMap { HomeContentSection(rawValue: String($0)) }
                .filter(allowed.contains)
        )
    }

    static func visibleSections(
        orderRawValue: String,
        hiddenRawValue: String
    ) -> [HomeContentSection] {
        let hidden = hiddenSections(from: hiddenRawValue)
        return [.recentlyPlayed] + orderedConfigurableSections(
            from: orderRawValue
        ).filter { !hidden.contains($0) }
    }

    static func moving(
        _ source: HomeContentSection,
        to target: HomeContentSection,
        in sections: [HomeContentSection]
    ) -> [HomeContentSection] {
        guard
            source != target,
            source != .recentlyPlayed,
            target != .recentlyPlayed,
            let sourceIndex = sections.firstIndex(of: source),
            let targetIndex = sections.firstIndex(of: target)
        else {
            return sections
        }
        var reordered = sections
        let section = reordered.remove(at: sourceIndex)
        reordered.insert(section, at: min(targetIndex, reordered.endIndex))
        return reordered
    }

    static func encode(
        _ sections: some Sequence<HomeContentSection>
    ) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }
}

struct ProductionHomeView: View {
    @Bindable var model: CadenceAppModel
    @Bindable var store: LibraryStore
    @AppStorage("home.pins.revision") var pinRevision = 0
    @AppStorage(CadencePreferences.Keys.homeSectionOrder)
    private var homeSectionOrderRawValue =
        HomeSectionConfiguration.defaultOrderRawValue
    @AppStorage(CadencePreferences.Keys.hiddenHomeSections)
    private var hiddenHomeSectionsRawValue = ""

    var body: some View {
        if store.availability == .loading,
           store.catalogCounts.liveTrackCount == 0 {
            ProgressView("Loading Home")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CadenceTheme.contentBackground)
        } else if store.catalogCounts.liveTrackCount == 0 {
            VStack(spacing: 0) {
                CadencePageHeader("Home", subtitle: "0 tracks")
                    .padding(CadenceLayout.pageInset)
                EmptyLibraryView(
                    title: "No Music Yet",
                    description: "Import music to start building your library."
                ) {
                    model.requestNavigationDestination(.importMusic)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CadenceTheme.contentBackground)
        } else {
            CadencePageScrollView(
                refreshAction: {
                    await store.refresh(.home)
                },
                content: {
                    CadencePageHeader(
                        "Home",
                        subtitle: "\(store.catalogCounts.liveTrackCount) tracks"
                    )

                    ForEach(visibleSections) { section in
                        switch section {
                        case .recentlyPlayed:
                            recentlyPlayed
                        case .pinned:
                            pinnedItems
                        case .favorites:
                            favorites
                        }
                    }
                    personalizationEmptyState
                }
            )
        }
    }

    @ViewBuilder
    var recentlyPlayed: some View {
        let tracks = HomeListeningSelection.recentItems(
            store.recentlyPlayedTracks,
            limit: 6
        )
        if !tracks.isEmpty {
            HomeShelf(title: "Recently Played") {
                HomeTrackGrid(
                    model: model,
                    tracks: tracks,
                    queueSource: .adHoc
                )
            }
        }
    }

    @ViewBuilder
    private var personalizationEmptyState: some View {
        if !hasPinnedItems,
           !hasRecentItems,
           store.favoriteTracks.isEmpty,
           store.favoriteAlbums.isEmpty,
           store.favoriteArtists.isEmpty {
            ContentUnavailableView {
                Label("Start Listening", systemImage: "waveform")
            } description: {
                Text("Recently played music, favorites, and shortcuts will appear here.")
            } actions: {
                Button("Browse All Tracks") {
                    model.requestNavigationDestination(.allTracks)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 264)
        }
    }

    private var hasRecentItems: Bool {
        !HomeListeningSelection.recentItems(
            store.recentlyPlayedTracks,
            limit: 1
        ).isEmpty
    }

    private var visibleSections: [HomeContentSection] {
        HomeSectionConfiguration.visibleSections(
            orderRawValue: homeSectionOrderRawValue,
            hiddenRawValue: hiddenHomeSectionsRawValue
        )
    }
}
