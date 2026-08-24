@testable import Cadence
import Foundation
import SwiftData
import Testing

@MainActor
struct FavoriteCatalogPaginationTests {
    @Test("Favoriting an off-page album reloads the resident page boundary")
    func offPageAlbumFavoriteReloadsResidentBoundary() async throws {
        let fixture = try makeFavoriteCatalogFixture()
        let store = LibraryStore(container: fixture.container)
        await store.loadInitialLibrary()
        let initialCursor = try #require(store.favoriteAlbumCursor)

        #expect(store.favoriteAlbums.count == 200)
        #expect(store.favoriteAlbums.first?.title == "B Album 000")
        #expect(store.favoriteAlbums.last?.title == "B Album 199")

        _ = try await store.setAlbumFavorite(
            id: fixture.offPageAlbumID,
            isFavorite: true
        )

        #expect(store.favoriteAlbums.count == 200)
        #expect(store.favoriteAlbums.first?.title == "A New Album")
        #expect(store.favoriteAlbums.last?.title == "B Album 198")
        #expect(store.favoriteAlbumCursor != initialCursor)
    }

    @Test("Favoriting an off-page artist reloads the resident page boundary")
    func offPageArtistFavoriteReloadsResidentBoundary() async throws {
        let fixture = try makeFavoriteCatalogFixture()
        let store = LibraryStore(container: fixture.container)
        await store.loadInitialLibrary()
        let initialCursor = try #require(store.favoriteArtistCursor)

        #expect(store.favoriteArtists.count == 200)
        #expect(store.favoriteArtists.first?.name == "B Artist 000")
        #expect(store.favoriteArtists.last?.name == "B Artist 199")

        _ = try await store.setArtistFavorite(
            id: fixture.offPageArtistID,
            isFavorite: true
        )

        #expect(store.favoriteArtists.count == 200)
        #expect(store.favoriteArtists.first?.name == "A New Artist")
        #expect(store.favoriteArtists.last?.name == "B Artist 198")
        #expect(store.favoriteArtistCursor != initialCursor)
    }

    @Test("An unfavorited album stays removed when page reload fails")
    func residentAlbumUnfavoriteSurvivesReloadFailure() async throws {
        let fixture = try makeFavoriteCatalogFixture()
        let store = LibraryStore(container: fixture.container)
        let repository = try #require(store.repository)
        await store.loadInitialLibrary()
        let initialCursor = try #require(store.favoriteAlbumCursor)

        _ = try await store.setAlbumFavorite(
            id: fixture.residentAlbumID,
            isFavorite: false,
            firstPageLoader: { _ in
                throw FavoriteCatalogReloadTestError.injected
            }
        )

        let durableAlbum = try await repository.album(
            id: fixture.residentAlbumID
        )
        #expect(durableAlbum?.isFavorite == false)
        #expect(!store.favoriteAlbums.contains {
            $0.id == fixture.residentAlbumID
        })
        #expect(store.favoriteAlbums.count == 199)
        #expect(store.favoriteAlbumCursor == initialCursor)
        #expect(store.canLoadMoreFavoriteAlbums)
        #expect(store.operationFailure == expectedReloadFailure)
    }

    @Test("An unfavorited artist stays removed when page reload fails")
    func residentArtistUnfavoriteSurvivesReloadFailure() async throws {
        let fixture = try makeFavoriteCatalogFixture()
        let store = LibraryStore(container: fixture.container)
        let repository = try #require(store.repository)
        await store.loadInitialLibrary()
        let initialCursor = try #require(store.favoriteArtistCursor)

        _ = try await store.setArtistFavorite(
            id: fixture.residentArtistID,
            isFavorite: false,
            firstPageLoader: { _ in
                throw FavoriteCatalogReloadTestError.injected
            }
        )

        let durableArtist = try await repository.artist(
            id: fixture.residentArtistID
        )
        #expect(durableArtist?.isFavorite == false)
        #expect(!store.favoriteArtists.contains {
            $0.id == fixture.residentArtistID
        })
        #expect(store.favoriteArtists.count == 199)
        #expect(store.favoriteArtistCursor == initialCursor)
        #expect(store.canLoadMoreFavoriteArtists)
        #expect(store.operationFailure == expectedReloadFailure)
    }
}

private extension FavoriteCatalogPaginationTests {
    struct Fixture {
        let container: ModelContainer
        let offPageAlbumID: UUID
        let offPageArtistID: UUID
        let residentAlbumID: UUID
        let residentArtistID: UUID
    }

    var expectedReloadFailure: LibraryOperationFailure {
        LibraryOperationFailure(
            operation: .favoriteCatalog,
            message: FavoriteCatalogReloadTestError.injected
                .localizedDescription
        )
    }

    func makeFavoriteCatalogFixture() throws -> Fixture {
        let container = try LibraryContainerFactory.inMemory()
        let context = ModelContext(container)
        let offPageArtist = ArtistRecord(name: "A New Artist")
        let offPageAlbum = AlbumRecord(title: "A New Album")
        let residentArtist = ArtistRecord(
            name: "B Artist 000",
            isFavorite: true,
            favoriteDate: .distantPast
        )
        let residentAlbum = AlbumRecord(
            title: "B Album 000",
            isFavorite: true,
            favoriteDate: .distantPast
        )
        context.insert(offPageArtist)
        context.insert(offPageAlbum)
        context.insert(residentArtist)
        context.insert(residentAlbum)

        for index in 1 ... 200 {
            let suffix = String(format: "%03d", index)
            context.insert(
                ArtistRecord(
                    name: "B Artist \(suffix)",
                    isFavorite: true,
                    favoriteDate: .distantPast
                )
            )
            context.insert(
                AlbumRecord(
                    title: "B Album \(suffix)",
                    isFavorite: true,
                    favoriteDate: .distantPast
                )
            )
        }

        try context.save()
        return Fixture(
            container: container,
            offPageAlbumID: offPageAlbum.id,
            offPageArtistID: offPageArtist.id,
            residentAlbumID: residentAlbum.id,
            residentArtistID: residentArtist.id
        )
    }
}

private enum FavoriteCatalogReloadTestError: LocalizedError {
    case injected

    var errorDescription: String? {
        "Injected favorite page reload failure."
    }
}
