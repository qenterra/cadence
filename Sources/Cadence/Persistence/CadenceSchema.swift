import SwiftData

enum CadenceSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static let models: [any PersistentModel.Type] = [
        AlbumRecord.self,
        ArtistRecord.self,
        ArtworkRecord.self,
        ImportSessionRecord.self,
        LyricRecord.self,
        SmartCollectionRecord.self,
        TagAssignmentRecord.self,
        TagExclusionRecord.self,
        TagRecord.self,
        TrackRecord.self,
    ]
}

enum CadenceSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static let models: [any PersistentModel.Type] = [
        AlbumRecord.self,
        ArtistRecord.self,
        ArtworkRecord.self,
        ImportSessionRecord.self,
        LyricRecord.self,
        SmartCollectionRecord.self,
        TagAssignmentRecord.self,
        TagExclusionRecord.self,
        TagRecord.self,
        TrackRecord.self,
        TrashOperationRecord.self,
    ]
}

enum CadenceSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

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
        TrackRecord.self,
        TrashOperationRecord.self,
    ]
}

enum CadenceMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        CadenceSchemaV1.self,
        CadenceSchemaV2.self,
        CadenceSchemaV3.self,
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
    ]
}
