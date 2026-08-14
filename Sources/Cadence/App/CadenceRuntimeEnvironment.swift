import Foundation

/// Owns every dependency and data set that may exist only in design previews.
/// Production construction cannot reach these values without selecting `.preview` explicitly.
struct CadencePreviewFixture {
    let tracks: [TrackPreview]
    let tags: [TagPreview]
    let tagAssignments: Set<TagAssignmentPreview>
    let tagExclusions: Set<TagExclusionPreview>
    let smartCollections: [SmartCollectionPreview]
    let lyricDocuments: [TrackPreview.ID: LyricDocument]
    let favoriteAlbumDates: [AlbumPreview.ID: Date]
    let favoriteArtistDates: [ArtistPreview.ID: Date]
    let importCandidates: [ImportCandidatePreview]
    let artworkRepository: any ArtworkRepository

    init(
        tracks: [TrackPreview] = [],
        tags: [TagPreview] = [],
        tagAssignments: Set<TagAssignmentPreview> = [],
        tagExclusions: Set<TagExclusionPreview> = [],
        smartCollections: [SmartCollectionPreview] = [],
        lyricDocuments: [TrackPreview.ID: LyricDocument] = [:],
        favoriteAlbumDates: [AlbumPreview.ID: Date] = [:],
        favoriteArtistDates: [ArtistPreview.ID: Date] = [:],
        importCandidates: [ImportCandidatePreview] = [],
        artworkRepository: any ArtworkRepository = InMemoryArtworkRepository()
    ) {
        self.tracks = tracks
        self.tags = tags
        self.tagAssignments = tagAssignments
        self.tagExclusions = tagExclusions
        self.smartCollections = smartCollections
        self.lyricDocuments = lyricDocuments
        self.favoriteAlbumDates = favoriteAlbumDates
        self.favoriteArtistDates = favoriteArtistDates
        self.importCandidates = importCandidates
        self.artworkRepository = artworkRepository
    }
}

/// Makes the production/preview boundary part of model construction instead of inferring it
/// from absent services, empty data, or an in-memory repository.
enum CadenceRuntimeEnvironment {
    case production
    case preview(CadencePreviewFixture)

    var mode: CadenceRuntimeMode {
        switch self {
        case .production: .production
        case .preview: .preview
        }
    }

    var previewFixture: CadencePreviewFixture? {
        guard case let .preview(fixture) = self else {
            return nil
        }
        return fixture
    }
}
