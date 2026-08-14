import SwiftData

/// Released schema models are an append-only compatibility contract. Never edit
/// a historical model to match the current one; add a new version and migration
/// so an on-disk store created by every prior Cadence version remains readable.
enum CadenceSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static let models: [any PersistentModel.Type] = [
        CadenceLegacySchemaModels.AlbumRecord.self,
        CadenceLegacySchemaModels.ArtistRecord.self,
        ArtworkRecord.self,
        ImportSessionRecord.self,
        CadenceLegacySchemaModels.LyricRecord.self,
        SmartCollectionRecord.self,
        TagAssignmentRecord.self,
        TagExclusionRecord.self,
        TagRecord.self,
        CadenceLegacySchemaModels.TrackRecord.self,
    ]
}

enum CadenceSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static let models: [any PersistentModel.Type] = [
        CadenceLegacySchemaModels.AlbumRecord.self,
        CadenceLegacySchemaModels.ArtistRecord.self,
        ArtworkRecord.self,
        ImportSessionRecord.self,
        CadenceLegacySchemaModels.LyricRecord.self,
        SmartCollectionRecord.self,
        TagAssignmentRecord.self,
        TagExclusionRecord.self,
        TagRecord.self,
        CadenceLegacySchemaModels.TrackRecord.self,
        TrashOperationRecord.self,
    ]
}

enum CadenceSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static let models: [any PersistentModel.Type] = [
        CadenceLegacySchemaModels.AlbumRecord.self,
        CadenceLegacySchemaModels.ArtistRecord.self,
        ArtworkRecord.self,
        ImportSessionRecord.self,
        CadenceLegacySchemaModels.LyricRecord.self,
        CadenceLegacySchemaModels.PlaylistEntryRecord.self,
        PlaylistRecord.self,
        SmartCollectionRecord.self,
        TagAssignmentRecord.self,
        TagExclusionRecord.self,
        TagRecord.self,
        CadenceLegacySchemaModels.TrackRecord.self,
        TrashOperationRecord.self,
    ]
}

enum CadenceSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static let models: [any PersistentModel.Type] = [
        CadenceLegacySchemaModels.AlbumRecord.self,
        CadenceLegacySchemaModels.ArtistRecord.self,
        ArtworkRecord.self,
        ImportSessionRecord.self,
        CadenceLegacySchemaModels.LyricRecord.self,
        CadenceLegacySchemaModels.PlaylistEntryRecord.self,
        PlaylistRecord.self,
        SmartCollectionRecord.self,
        TagAssignmentRecord.self,
        TagExclusionRecord.self,
        TagRecord.self,
        TrackArtistCreditRecord.self,
        CadenceLegacySchemaModels.TrackRecord.self,
        TrashOperationRecord.self,
    ]
}

enum CadenceSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static let models: [any PersistentModel.Type] = [
        AlbumRecord.self,
        ArtistRecord.self,
        ArtworkRecord.self,
        ImportSessionRecord.self,
        LyricRecord.self,
        PlaylistEntryRecord.self,
        PlaylistRecord.self,
        SmartCollectionRecord.self,
        TagAssignmentRecord.self,
        TagExclusionRecord.self,
        TagRecord.self,
        TrackArtistCreditRecord.self,
        TrackRecord.self,
        TrashOperationRecord.self,
    ]
}

enum CadenceMigrationPlan: SchemaMigrationPlan {
    /// Keep every intermediate edge explicit. Skipping a version would make the
    /// result depend on which historical Cadence build last opened the library.
    static let schemas: [any VersionedSchema.Type] = [
        CadenceSchemaV1.self,
        CadenceSchemaV2.self,
        CadenceSchemaV3.self,
        CadenceSchemaV4.self,
        CadenceSchemaV5.self,
    ]

    static let stages: [MigrationStage] = [
        .lightweight(
            fromVersion: CadenceSchemaV1.self,
            toVersion: CadenceSchemaV2.self
        ),
        .lightweight(
            fromVersion: CadenceSchemaV2.self,
            toVersion: CadenceSchemaV3.self
        ),
        .lightweight(
            fromVersion: CadenceSchemaV3.self,
            toVersion: CadenceSchemaV4.self
        ),
        .lightweight(
            fromVersion: CadenceSchemaV4.self,
            toVersion: CadenceSchemaV5.self
        ),
    ]
}
