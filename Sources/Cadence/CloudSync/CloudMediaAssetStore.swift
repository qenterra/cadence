import CloudKit
import Foundation

actor CloudMediaAssetStore {
    static let chunkSize = 32 * 1024 * 1024

    private let libraryID: UUID
    private let package: ManagedLibraryPackage
    private let database: CKDatabase
    private let stagingDirectory: URL
    private let hasher: ContentHasher

    init(
        libraryID: UUID,
        package: ManagedLibraryPackage,
        stagingDirectory: URL,
        container: CKContainer,
        hasher: ContentHasher = ContentHasher()
    ) {
        self.libraryID = libraryID
        self.package = package
        database = container.privateCloudDatabase
        self.stagingDirectory = stagingDirectory
        self.hasher = hasher
    }

    func uploadMissingAssets(
        assets: [CloudManagedAssetDescriptor]
    ) async throws {
        for asset in assets {
            let source = try package.location.resolve(
                relativePath: asset.relativePath,
                directoryHint: .notDirectory
            )
            guard FileManager.default.fileExists(atPath: source.path),
                  try await !manifestExists(contentHash: asset.contentHash)
            else {
                continue
            }
            try await upload(
                source,
                contentHash: asset.contentHash
            )
        }
    }

    func download(
        contentHash: String,
        to destination: URL
    ) async throws -> URL? {
        let manifestID = recordID(
            name: "media.manifest.\(contentHash)"
        )
        let manifest: CKRecord
        do {
            manifest = try await database.record(for: manifestID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        guard let count = manifest.encryptedValues["chunkCount"] as? Int64,
              count > 0 else {
            return nil
        }
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        let staged = stagingDirectory.appending(
            path: "\(UUID().uuidString).download",
            directoryHint: .notDirectory
        )
        FileManager.default.createFile(atPath: staged.path, contents: nil)
        let writer = try FileHandle(forWritingTo: staged)
        defer { try? writer.close() }

        do {
            for index in 0 ..< Int(count) {
                let chunk = try await database.record(
                    for: recordID(
                        name: "media.chunk.\(contentHash).\(index)"
                    )
                )
                guard let asset = chunk.encryptedValues["asset"] as? CKAsset,
                      let fileURL = asset.fileURL else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try writer.write(contentsOf: Data(contentsOf: fileURL))
            }
            try writer.synchronize()
            let downloadedHash = try await hasher.sha256(of: staged)
            guard downloadedHash == contentHash else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staged, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }
}

private extension CloudMediaAssetStore {
    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: CloudKitLibrarySyncEngine.zoneName)
    }

    func manifestExists(
        contentHash: String
    ) async throws -> Bool {
        do {
            _ = try await database.record(
                for: recordID(name: "media.manifest.\(contentHash)")
            )
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        }
    }

    func upload(
        _ source: URL,
        contentHash: String
    ) async throws {
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        var chunkIndex = 0
        while let data = try reader.read(upToCount: Self.chunkSize),
              !data.isEmpty {
            let temporary = stagingDirectory.appending(
                path: "\(UUID().uuidString).chunk",
                directoryHint: .notDirectory
            )
            try data.write(to: temporary, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let record = CKRecord(
                recordType: "CadenceMediaChunk",
                recordID: recordID(
                    name: "media.chunk.\(contentHash).\(chunkIndex)"
                )
            )
            record.encryptedValues["libraryID"] = libraryID.uuidString as CKRecordValue
            record.encryptedValues["contentHash"] = contentHash as CKRecordValue
            record.encryptedValues["index"] = Int64(chunkIndex) as CKRecordValue
            record.encryptedValues["asset"] = CKAsset(fileURL: temporary)
            _ = try await database.save(record)
            chunkIndex += 1
        }
        guard chunkIndex > 0 else {
            return
        }
        let manifest = CKRecord(
            recordType: "CadenceMediaManifest",
            recordID: recordID(name: "media.manifest.\(contentHash)")
        )
        manifest.encryptedValues["libraryID"] = libraryID.uuidString as CKRecordValue
        manifest.encryptedValues["contentHash"] = contentHash as CKRecordValue
        manifest.encryptedValues["chunkCount"] = Int64(chunkIndex) as CKRecordValue
        _ = try await database.save(manifest)
    }

    func recordID(
        name: String
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }
}

@MainActor
final class CloudMediaPlaybackSource {
    private let repository: LibraryRepository
    private let package: ManagedLibraryPackage
    private let assetStore: CloudMediaAssetStore

    init(
        repository: LibraryRepository,
        package: ManagedLibraryPackage,
        assetStore: CloudMediaAssetStore
    ) {
        self.repository = repository
        self.package = package
        self.assetStore = assetStore
    }

    func resolve(
        tracks: [PlaybackTrack]
    ) async throws -> [UUID: URL] {
        let descriptors = try await repository.cloudMediaDescriptors(
            ids: tracks.map(\.id)
        )
        let descriptorsByID = Dictionary(
            uniqueKeysWithValues: descriptors.map { ($0.id, $0) }
        )
        var resolved: [UUID: URL] = [:]
        for track in tracks {
            guard let descriptor = descriptorsByID[track.id] else {
                continue
            }
            let destination = try package.location.resolve(
                relativePath: track.relativeMediaPath,
                directoryHint: .notDirectory
            )
            if let url = try await assetStore.download(
                contentHash: descriptor.contentHash,
                to: destination
            ) {
                resolved[track.id] = url
            }
        }
        return resolved
    }

    func synchronizeAssets() async throws {
        let assets = try await repository.cloudManagedAssetDescriptors()
        try await assetStore.uploadMissingAssets(assets: assets)
        try await materializeMissingAssets(
            assets.filter { $0.kind != .audio }
        )
    }

    func downloadAllOriginals() async throws {
        let assets = try await repository.cloudManagedAssetDescriptors()
        try await materializeMissingAssets(assets)
    }

    private func materializeMissingAssets(
        _ assets: [CloudManagedAssetDescriptor]
    ) async throws {
        for asset in assets {
            let destination = try package.location.resolve(
                relativePath: asset.relativePath,
                directoryHint: .notDirectory
            )
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }
            _ = try await assetStore.download(
                contentHash: asset.contentHash,
                to: destination
            )
        }
    }
}

@MainActor
final class CloudMediaPlaybackSourceRegistry {
    var source: CloudMediaPlaybackSource?

    init(source: CloudMediaPlaybackSource? = nil) {
        self.source = source
    }
}
