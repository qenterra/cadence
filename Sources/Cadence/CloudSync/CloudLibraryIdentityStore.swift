import CloudKit
import Foundation

enum CloudLibraryIdentityError: Error, LocalizedError {
    case conflictingLibrary(local: UUID, remote: UUID)

    var errorDescription: String? {
        switch self {
        case let .conflictingLibrary(local, remote):
            "This Mac has library \(local), but iCloud contains library \(remote). "
                + "Cadence left both libraries unchanged."
        }
    }
}

actor CloudLibraryIdentityStore {
    private static let recordID = CKRecord.ID(
        recordName: "primary-library"
    )

    private let database: CKDatabase

    init(
        container: CKContainer = CKContainer(
            identifier: CloudKitLibrarySyncEngine.containerIdentifier
        )
    ) {
        database = container.privateCloudDatabase
    }

    func remoteIdentity() async throws -> LibraryIdentity? {
        do {
            let record = try await database.record(for: Self.recordID)
            guard let idValue = record.encryptedValues["libraryID"] as? String,
                  let id = UUID(uuidString: idValue),
                  let format = record.encryptedValues["formatVersion"] as? Int64
            else {
                throw CocoaError(.coderReadCorrupt)
            }
            return LibraryIdentity(id: id, formatVersion: Int(format))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func register(
        _ identity: LibraryIdentity
    ) async throws {
        if let remote = try await remoteIdentity() {
            guard remote == identity else {
                throw CloudLibraryIdentityError.conflictingLibrary(
                    local: identity.id,
                    remote: remote.id
                )
            }
            return
        }
        let record = CKRecord(
            recordType: "CadenceLibraryIdentity",
            recordID: Self.recordID
        )
        record.encryptedValues["libraryID"] = identity.id.uuidString as CKRecordValue
        record.encryptedValues["formatVersion"] = Int64(identity.formatVersion) as CKRecordValue
        _ = try await database.save(record)
    }
}
