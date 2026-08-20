@testable import Cadence
import Foundation
import SwiftData

struct ManagedLyricsFixture {
    let rootURL: URL
    let package: ManagedLibraryPackage
    let repository: LibraryRepository
    let service: ManagedLyricsService
    let trackID: UUID
    let localCatalogRootURL: URL

    init() throws {
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
        trackID = UUID()
        let context = ModelContext(container)
        context.insert(
            TrackRecord(
                id: trackID,
                originalFilename: "Track.flac",
                title: "Track",
                duration: 180,
                codec: "FLAC",
                container: "FLAC",
                sampleRate: 48000,
                channelCount: 2,
                bitDepth: 24,
                contentHash: String(repeating: "a", count: 64),
                relativeMediaPath: "Media/\(trackID.uuidString).flac",
                importSessionID: UUID()
            )
        )
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
