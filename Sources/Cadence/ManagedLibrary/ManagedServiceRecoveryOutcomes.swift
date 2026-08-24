import Foundation

enum ManagedLyricsServiceError: Error, Equatable, LocalizedError, Sendable {
    case wrongTrackIdentity
    case invalidDocument(String)
    case unavailable
    case unreadableManagedLyrics
    case contentHashMismatch
    case inconsistentRecovery(UUID)

    var errorDescription: String? {
        switch self {
        case .wrongTrackIdentity:
            "The lyric draft no longer belongs to the selected track."
        case let .invalidDocument(message):
            "The lyric document is invalid: \(message)"
        case .unavailable:
            "Managed lyrics are unavailable for this library."
        case .unreadableManagedLyrics:
            "The managed lyric file could not be read as UTF-8."
        case .contentHashMismatch:
            "The managed lyric file changed outside Cadence."
        case let .inconsistentRecovery(operationID):
            "Lyrics recovery \(operationID.uuidString) is inconsistent."
        }
    }
}

struct ManagedLyricsRecoveryResult: Equatable, Sendable {
    let recoveredOperationIDs: [UUID]
    let rolledBackOperationIDs: [UUID]
    let affectedTrackIDs: [UUID]

    static let empty = ManagedLyricsRecoveryResult(
        recoveredOperationIDs: [],
        rolledBackOperationIDs: [],
        affectedTrackIDs: []
    )
}

protocol ManagedLyricsRecoveryCarryingError: Error, Sendable {
    var recovery: ManagedLyricsRecoveryResult { get }
    var underlyingError: any Error { get }
}

struct ManagedLyricsSaveFailure: ManagedLyricsRecoveryCarryingError,
    LocalizedError {
    let recovery: ManagedLyricsRecoveryResult
    let underlyingError: any Error

    var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

struct ManagedLyricsLoadResult: Sendable {
    let document: LyricDocument?
    let didRepairMetadata: Bool
}

struct ManagedLyricsSaveResult: Equatable, Sendable {
    let recovery: ManagedLyricsRecoveryResult
    let affectedTrackIDs: [UUID]

    init(
        recovery: ManagedLyricsRecoveryResult,
        savedTrackID: UUID
    ) {
        self.recovery = recovery
        var affectedTrackIDs = recovery.affectedTrackIDs
        if !affectedTrackIDs.contains(savedTrackID) {
            affectedTrackIDs.append(savedTrackID)
        }
        self.affectedTrackIDs = affectedTrackIDs
    }
}

struct ManagedArtworkPublicationEffect: Equatable, Sendable {
    let ownerKind: ArtworkOwnerKind
    let ownerID: UUID
    let previousArtworkID: UUID?
    let newArtworkID: UUID?
}

struct ManagedArtworkRecoveryResult: Equatable, Sendable {
    let recoveredOperationIDs: [UUID]
    let rolledBackOperationIDs: [UUID]
    let effects: [ManagedArtworkPublicationEffect]

    static let empty = ManagedArtworkRecoveryResult(
        recoveredOperationIDs: [],
        rolledBackOperationIDs: [],
        effects: []
    )
}

protocol ManagedArtworkRecoveryCarryingError: Error, Sendable {
    var recovery: ManagedArtworkRecoveryResult { get }
    var underlyingError: any Error { get }
}

struct ManagedArtworkMutationFailure: ManagedArtworkRecoveryCarryingError,
    LocalizedError {
    let recovery: ManagedArtworkRecoveryResult
    let underlyingError: any Error

    var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

struct ManagedArtworkMutationResult: Equatable, Sendable {
    let primaryArtworkID: UUID?
    let effects: [ManagedArtworkPublicationEffect]
}

extension ManagedLyricsService {
    func carryingRecovery(
        _ recovery: ManagedLyricsRecoveryResult,
        after error: any Error
    ) -> any Error {
        guard recovery != .empty else {
            return error
        }
        guard !(error is any ManagedLyricsRecoveryCarryingError) else {
            return error
        }
        return ManagedLyricsSaveFailure(
            recovery: recovery,
            underlyingError: error
        )
    }
}

extension ManagedArtworkService {
    func carryingRecovery(
        _ recovery: ManagedArtworkRecoveryResult,
        after error: any Error
    ) -> any Error {
        guard recovery != .empty else {
            return error
        }
        guard !(error is any ManagedArtworkRecoveryCarryingError) else {
            return error
        }
        return ManagedArtworkMutationFailure(
            recovery: recovery,
            underlyingError: error
        )
    }
}
