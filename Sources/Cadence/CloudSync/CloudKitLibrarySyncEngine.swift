import CloudKit
import Foundation

private struct CloudKitLibraryDiskState: Codable {
    var records: [String: CloudLibraryRecord] = [:]
    var stateSerialization: CKSyncEngine.State.Serialization?
}

actor CloudKitLibrarySyncEngine: CKSyncEngineDelegate {
    typealias RemoteChangeHandler = @Sendable (
        [CloudLibraryRecord]
    ) async throws -> Void

    static let containerIdentifier = "iCloud.com.qenterra.cadence"
    static let zoneName = "CadenceLibrary"
    static let recordType: CKRecord.RecordType = "CadenceEntity"

    private let libraryID: UUID
    private let deviceID: UUID
    private let stateURL: URL
    private let container: CKContainer
    private let remoteChangeHandler: RemoteChangeHandler
    private var diskState: CloudKitLibraryDiskState
    private var engine: CKSyncEngine?

    init(
        libraryID: UUID,
        deviceID: UUID,
        stateURL: URL,
        container: CKContainer = CKContainer(
            identifier: CloudKitLibrarySyncEngine.containerIdentifier
        ),
        remoteChangeHandler: @escaping RemoteChangeHandler
    ) {
        self.libraryID = libraryID
        self.deviceID = deviceID
        self.stateURL = stateURL
        self.container = container
        self.remoteChangeHandler = remoteChangeHandler
        diskState = (try? Data(contentsOf: stateURL))
            .flatMap { try? JSONDecoder().decode(CloudKitLibraryDiskState.self, from: $0) }
            ?? CloudKitLibraryDiskState()
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    func synchronize(
        repository: LibraryRepository
    ) async throws {
        let engine = syncEngine()
        try await engine.fetchChanges()
        let entities = try await repository.exportCloudEntities()
        try saveLocalSnapshot(entities)
        try await engine.sendChanges()
    }

    func handleEvent(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        do {
            switch event {
            case let .stateUpdate(update):
                diskState.stateSerialization = update.stateSerialization
                try persist()
            case let .fetchedRecordZoneChanges(changes):
                try await mergeFetchedChanges(changes)
            case let .sentRecordZoneChanges(changes):
                try handleSentChanges(changes, syncEngine: syncEngine)
            case let .accountChange(change):
                try handleAccountChange(change, syncEngine: syncEngine)
            case let .fetchedDatabaseChanges(changes):
                if changes.deletions.contains(where: {
                    $0.zoneID.zoneName == Self.zoneName
                }) {
                    scheduleFullUpload(syncEngine)
                }
            case .sentDatabaseChanges,
                 .willFetchChanges,
                 .willFetchRecordZoneChanges,
                 .didFetchRecordZoneChanges,
                 .didFetchChanges,
                 .willSendChanges,
                 .didSendChanges:
                break
            @unknown default:
                break
            }
        } catch {
            // CKSyncEngine retries transport failures. Persistence and merge
            // errors remain represented by the pending state for the next run.
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        let records = diskState.records
        return await CKSyncEngine.RecordZoneChangeBatch(
            pendingChanges: pending
        ) { recordID in
            guard let value = records[recordID.recordName] else {
                syncEngine.state.remove(
                    pendingRecordZoneChanges: [.saveRecord(recordID)]
                )
                return nil
            }
            let record = value.lastKnownRecord
                ?? CKRecord(
                    recordType: Self.recordType,
                    recordID: recordID
                )
            value.populate(record)
            return record
        }
    }
}

private extension CloudKitLibrarySyncEngine {
    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName)
    }

    func syncEngine() -> CKSyncEngine {
        if let engine {
            return engine
        }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: diskState.stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if diskState.stateSerialization == nil {
            engine.state.add(
                pendingDatabaseChanges: [
                    .saveZone(CKRecordZone(zoneID: zoneID)),
                ]
            )
        }
        return engine
    }

    func saveLocalSnapshot(
        _ entities: [CloudLibraryEntity],
        now: Date = .now
    ) throws {
        let entityNames = Set(entities.map(recordName(for:)))
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []

        for entity in entities {
            let name = recordName(for: entity)
            if let existing = diskState.records[name],
               !existing.isTombstone,
               existing.payload == entity.payload {
                continue
            }
            var record = CloudLibraryRecord.live(
                libraryID: libraryID,
                entity: entity,
                modifiedAt: now,
                deviceID: deviceID
            )
            record.lastKnownRecordData = diskState.records[name]?.lastKnownRecordData
            diskState.records[name] = record
            pending.append(.saveRecord(recordID(for: name)))
        }

        for (name, existing) in diskState.records where
            existing.libraryID == libraryID
            && !existing.isTombstone
            && !entityNames.contains(name) {
            diskState.records[name] = .tombstone(
                replacing: existing,
                modifiedAt: now,
                deviceID: deviceID
            )
            pending.append(.saveRecord(recordID(for: name)))
        }
        try persist()
        syncEngine().state.add(pendingRecordZoneChanges: pending)
    }

    func mergeFetchedChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) async throws {
        var applied: [CloudLibraryRecord] = []
        for modification in event.modifications {
            let ckRecord = modification.record
            guard var remote = CloudLibraryRecord(record: ckRecord),
                  remote.libraryID == libraryID else {
                continue
            }
            remote.setLastKnownRecordIfNewer(ckRecord)
            if let local = diskState.records[remote.recordName] {
                let preferred = CloudLibraryConflictResolver.preferred(
                    local: local,
                    remote: remote
                )
                diskState.records[remote.recordName] = preferred
                if preferred == local,
                   preferred.payload != remote.payload {
                    syncEngine().state.add(
                        pendingRecordZoneChanges: [
                            .saveRecord(recordID(for: preferred.recordName)),
                        ]
                    )
                } else if preferred == remote {
                    applied.append(remote)
                }
            } else {
                diskState.records[remote.recordName] = remote
                applied.append(remote)
            }
        }
        // Physical CloudKit deletions are converted to durable tombstones when
        // possible. Normal Cadence deletion never removes the record itself.
        for deletion in event.deletions {
            guard let existing = diskState.records[deletion.recordID.recordName] else {
                continue
            }
            let tombstone = CloudLibraryRecord.tombstone(
                replacing: existing,
                modifiedAt: .now,
                deviceID: deviceID
            )
            diskState.records[tombstone.recordName] = tombstone
            applied.append(tombstone)
        }
        try persist()
        if !applied.isEmpty {
            try await remoteChangeHandler(applied)
        }
    }

    func handleSentChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) throws {
        for record in event.savedRecords {
            guard var value = diskState.records[record.recordID.recordName] else {
                continue
            }
            value.setLastKnownRecordIfNewer(record)
            diskState.records[value.recordName] = value
        }
        var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
        var recordChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        for failure in event.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord,
                      var remote = CloudLibraryRecord(record: server),
                      let local = diskState.records[id.recordName] else {
                    continue
                }
                remote.setLastKnownRecordIfNewer(server)
                let preferred = CloudLibraryConflictResolver.preferred(
                    local: local,
                    remote: remote
                )
                diskState.records[id.recordName] = preferred
                if preferred == local {
                    recordChanges.append(.saveRecord(id))
                }
            case .zoneNotFound:
                databaseChanges.append(.saveZone(CKRecordZone(zoneID: zoneID)))
                recordChanges.append(.saveRecord(id))
            case .unknownItem:
                if var local = diskState.records[id.recordName] {
                    local.lastKnownRecordData = nil
                    diskState.records[id.recordName] = local
                    recordChanges.append(.saveRecord(id))
                }
            default:
                break
            }
        }
        syncEngine.state.add(pendingDatabaseChanges: databaseChanges)
        syncEngine.state.add(pendingRecordZoneChanges: recordChanges)
        try persist()
    }

    func handleAccountChange(
        _ event: CKSyncEngine.Event.AccountChange,
        syncEngine: CKSyncEngine
    ) throws {
        switch event.changeType {
        case .signIn:
            scheduleFullUpload(syncEngine)
        case .switchAccounts, .signOut:
            // The local replica is intentionally retained. A different iCloud
            // account must never silently erase a user's offline library.
            engine = nil
            diskState.stateSerialization = nil
            try persist()
        @unknown default:
            break
        }
    }

    func scheduleFullUpload(
        _ engine: CKSyncEngine
    ) {
        engine.state.add(
            pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: zoneID)),
            ]
        )
        engine.state.add(
            pendingRecordZoneChanges: diskState.records.values
                .filter { $0.libraryID == libraryID }
                .map { .saveRecord(recordID(for: $0.recordName)) }
        )
    }

    func recordName(
        for entity: CloudLibraryEntity
    ) -> String {
        "\(libraryID.uuidString).\(entity.kind.rawValue).\(entity.id.uuidString)"
    }

    func recordID(
        for name: String
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    func persist() throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(diskState)
        try data.write(to: stateURL, options: .atomic)
    }
}

private extension CloudLibraryRecord {
    init?(record: CKRecord) {
        guard
            let libraryIDString = record.encryptedValues["libraryID"] as? String,
            let libraryID = UUID(uuidString: libraryIDString),
            let kindRawValue = record.encryptedValues["entityKind"] as? String,
            let entityKind = CloudLibraryEntityKind(rawValue: kindRawValue),
            let entityIDString = record.encryptedValues["entityID"] as? String,
            let entityID = UUID(uuidString: entityIDString),
            let payload = record.encryptedValues["payload"] as? Data,
            let userModificationDate = record.encryptedValues["userModificationDate"] as? Date,
            let deviceIDString = record.encryptedValues["deviceID"] as? String,
            let deviceID = UUID(uuidString: deviceIDString),
            let isTombstone = record.encryptedValues["isTombstone"] as? Int64
        else {
            return nil
        }
        self.init(
            libraryID: libraryID,
            entityKind: entityKind,
            entityID: entityID,
            payload: payload,
            userModificationDate: userModificationDate,
            deviceID: deviceID,
            isTombstone: isTombstone != 0
        )
    }

    func populate(
        _ record: CKRecord
    ) {
        record.encryptedValues["libraryID"] = libraryID.uuidString as CKRecordValue
        record.encryptedValues["entityKind"] = entityKind.rawValue as CKRecordValue
        record.encryptedValues["entityID"] = entityID.uuidString as CKRecordValue
        record.encryptedValues["payload"] = payload as CKRecordValue
        record.encryptedValues["userModificationDate"] = userModificationDate as CKRecordValue
        record.encryptedValues["deviceID"] = deviceID.uuidString as CKRecordValue
        record.encryptedValues["isTombstone"] = Int64(isTombstone ? 1 : 0) as CKRecordValue
    }

    var lastKnownRecord: CKRecord? {
        guard let lastKnownRecordData,
              let unarchiver = try? NSKeyedUnarchiver(
                  forReadingFrom: lastKnownRecordData
              ) else {
            return nil
        }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }

    mutating func setLastKnownRecordIfNewer(
        _ record: CKRecord
    ) {
        if let localDate = lastKnownRecord?.modificationDate,
           let remoteDate = record.modificationDate,
           localDate >= remoteDate {
            return
        }
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        lastKnownRecordData = archiver.encodedData
    }
}
