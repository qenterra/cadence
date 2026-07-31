@testable import Cadence
import Foundation

extension CadenceAppModel {
    static func testFixture(
        tracks: [TrackPreview] = .mockLibrary,
        tags: [TagPreview] = .mockTags,
        tagAssignments: Set<TagAssignmentPreview> = .mockTagAssignments,
        tagExclusions: Set<TagExclusionPreview> = .mockTagExclusions,
        smartCollections: [SmartCollectionPreview] = .mockSmartCollections,
        lyricDocuments: [TrackPreview.ID: LyricDocument] = .mockLyrics,
        favoriteAlbumDates: [AlbumPreview.ID: Date] = .mockAlbumFavorites,
        favoriteArtistDates: [ArtistPreview.ID: Date] = .mockArtistFavorites,
        importCandidates: [ImportCandidatePreview] = .mockImportCandidates,
        artworkRepository: any ArtworkRepository = InMemoryArtworkRepository()
    ) -> CadenceAppModel {
        .preview(
            tracks: tracks,
            tags: tags,
            tagAssignments: tagAssignments,
            tagExclusions: tagExclusions,
            smartCollections: smartCollections,
            lyricDocuments: lyricDocuments,
            favoriteAlbumDates: favoriteAlbumDates,
            favoriteArtistDates: favoriteArtistDates,
            importCandidates: importCandidates,
            artworkRepository: artworkRepository
        )
    }
}
