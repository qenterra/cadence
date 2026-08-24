@testable import Cadence
import Foundation
import SwiftData

struct ManagedLyricsFixture {
    let rootURL: URL
    let package: ManagedLibraryPackage
    let repository: LibraryRepository
    let service: ManagedLyricsService
    let trackID: UUID
    let additionalTrackIDs: [UUID]
    let localCatalogRootURL: URL

    init(trackCount: Int = 1) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "CadenceLyricsTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let musicURL = rootURL.appending(
            path: "Music",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: musicURL,
            withIntermediateDirectories: true
        )
        package = ManagedLibraryPackage(
            location: ManagedLibraryLocation(musicDirectory: musicURL)
        )
        try package.bootstrapForConfirmedImport()
        let identity = LibraryIdentity()
        try package.writeIdentity(identity)
        localCatalogRootURL = try LocalLibraryCatalogLocation.currentUser(
            identity: identity
        ).rootURL

        let container = try LibraryContainerFactory.inMemory()
        repository = LibraryRepository(modelContainer: container)
        let trackIDs = (0 ..< max(trackCount, 1)).map { _ in UUID() }
        trackID = trackIDs[0]
        additionalTrackIDs = Array(trackIDs.dropFirst())
        let context = ModelContext(container)
        for (index, id) in trackIDs.enumerated() {
            let isPrimaryTrack = index == 0
            context.insert(
                TrackRecord(
                    id: id,
                    originalFilename: isPrimaryTrack
                        ? "Track.flac"
                        : "Track \(index + 1).flac",
                    title: isPrimaryTrack ? "Track" : "Track \(index + 1)",
                    duration: 180,
                    codec: "FLAC",
                    container: "FLAC",
                    sampleRate: 48000,
                    channelCount: 2,
                    bitDepth: 24,
                    contentHash: isPrimaryTrack
                        ? String(repeating: "a", count: 64)
                        : String(format: "%064x", index + 1),
                    relativeMediaPath: "Media/\(id.uuidString).flac",
                    importSessionID: UUID()
                )
            )
        }
        try context.save()
        service = ManagedLyricsService(
            package: package,
            repository: repository
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
        try? FileManager.default.removeItem(at: localCatalogRootURL)
    }
}
