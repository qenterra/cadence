@testable import Cadence
import Foundation
import Testing

struct ManagedLibraryLocationTests {
    @Test("Managed library resolves to the injected Music directory")
    func canonicalPackageURL() {
        let musicDirectory = URL(
            filePath: "/Users/Shared/ExampleMusic",
            directoryHint: .isDirectory
        )
        let location = ManagedLibraryLocation(
            musicDirectory: musicDirectory
        )

        #expect(
            location.packageURL
                == musicDirectory.appending(
                    path: "Cadence.library",
                    directoryHint: .isDirectory
                )
        )
    }

    @Test("Constructing a managed library location has no filesystem side effects")
    func constructionIsReadOnly() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )

            #expect(
                !FileManager.default.fileExists(
                    atPath: location.packageURL.path
                )
            )
        }
    }

    @Test("Relative managed paths cannot escape the package")
    func pathContainment() throws {
        let location = ManagedLibraryLocation(
            musicDirectory: URL(
                filePath: "/Users/Shared/ExampleMusic",
                directoryHint: .isDirectory
            )
        )

        let mediaURL = try location.resolve(
            relativePath: "Media/track.flac"
        )
        #expect(
            mediaURL
                == location.packageURL.appending(
                    path: "Media/track.flac",
                    directoryHint: .notDirectory
                )
        )

        #expect(throws: ManagedLibraryError.self) {
            try location.resolve(relativePath: "../outside.flac")
        }
        #expect(throws: ManagedLibraryError.self) {
            try location.resolve(relativePath: "/tmp/outside.flac")
        }
        #expect(throws: ManagedLibraryError.self) {
            try location.resolve(relativePath: "Media//track.flac")
        }
    }

    @Test("A missing managed file resolves beneath an existing package")
    func missingManagedFileResolvesInsideExistingPackage() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
            let package = ManagedLibraryPackage(location: location)
            let relativePath = "Media/70C93E9A-CCB2-4C45-91B7-B3194441319A.flac"

            try package.bootstrapForConfirmedImport()

            let mediaURL = try location.resolve(relativePath: relativePath)

            #expect(
                mediaURL
                    == location.packageURL.appending(
                        path: relativePath,
                        directoryHint: .notDirectory
                    )
            )
            #expect(!FileManager.default.fileExists(atPath: mediaURL.path))
        }
    }

    @Test("A managed directory symlink cannot leave the package")
    func managedDirectorySymlinkCannotEscapePackage() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
            let package = ManagedLibraryPackage(location: location)
            let outsideDirectory = musicDirectory.appending(
                path: "OutsideMedia",
                directoryHint: .isDirectory
            )

            try package.bootstrapForConfirmedImport()
            try FileManager.default.createDirectory(
                at: outsideDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.removeItem(at: package.mediaDirectoryURL)
            try FileManager.default.createSymbolicLink(
                at: package.mediaDirectoryURL,
                withDestinationURL: outsideDirectory
            )

            #expect(throws: ManagedLibraryError.self) {
                try location.resolve(relativePath: "Media/track.flac")
            }
        }
    }

    @Test("An existing managed file symlink cannot leave the package")
    func managedFileSymlinkCannotEscapePackage() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
            let package = ManagedLibraryPackage(location: location)
            let outsideFile = musicDirectory.appending(
                path: "outside.flac",
                directoryHint: .notDirectory
            )
            let managedFile = package.mediaDirectoryURL.appending(
                path: "track.flac",
                directoryHint: .notDirectory
            )

            try package.bootstrapForConfirmedImport()
            try Data([0]).write(to: outsideFile)
            try FileManager.default.createSymbolicLink(
                at: managedFile,
                withDestinationURL: outsideFile
            )

            #expect(throws: ManagedLibraryError.self) {
                try location.resolve(relativePath: "Media/track.flac")
            }
        }
    }

    @Test("Confirmed bootstrap creates the exact package layout")
    func confirmedBootstrap() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
            let package = ManagedLibraryPackage(location: location)

            try package.bootstrapForConfirmedImport()
            try package.bootstrapForConfirmedImport()

            let expectedDirectories = [
                location.packageURL,
                package.mediaDirectoryURL,
                package.lyricsDirectoryURL,
                package.artworkOriginalDirectoryURL,
                package.artworkThumbnailsDirectoryURL,
                package.metadataDirectoryURL,
                package.stagingDirectoryURL,
            ]

            for directory in expectedDirectories {
                var isDirectory: ObjCBool = false
                #expect(
                    FileManager.default.fileExists(
                        atPath: directory.path,
                        isDirectory: &isDirectory
                    )
                )
                #expect(isDirectory.boolValue)
            }
        }
    }

    @Test("Managed audio and lyric filenames use the track UUID")
    func managedAssetNames() throws {
        let location = ManagedLibraryLocation(
            musicDirectory: URL(
                filePath: "/Users/Shared/ExampleMusic",
                directoryHint: .isDirectory
            )
        )
        let package = ManagedLibraryPackage(location: location)
        let trackID = UUID(uuidString: "70C93E9A-CCB2-4C45-91B7-B3194441319A")
        let requiredTrackID = try #require(trackID)

        #expect(
            try package.mediaURL(
                trackID: requiredTrackID,
                originalExtension: "FLAC"
            ).lastPathComponent
                == "70C93E9A-CCB2-4C45-91B7-B3194441319A.flac"
        )
        #expect(
            package.lyricURL(trackID: requiredTrackID).lastPathComponent
                == "70C93E9A-CCB2-4C45-91B7-B3194441319A.lrc"
        )
        #expect(throws: ManagedLibraryError.self) {
            try package.mediaURL(
                trackID: requiredTrackID,
                originalExtension: "../flac"
            )
        }
        #expect(throws: ManagedLibraryError.self) {
            try package.mediaURL(
                trackID: requiredTrackID,
                originalExtension: "exe"
            )
        }
    }

    @Test("Bootstrap rejects a file colliding with a required directory")
    func layoutCollision() throws {
        try withTemporaryDirectory { musicDirectory in
            let location = ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
            let package = ManagedLibraryPackage(location: location)

            try FileManager.default.createDirectory(
                at: location.packageURL,
                withIntermediateDirectories: true
            )
            let mediaCollision = package.mediaDirectoryURL
            try Data([0]).write(to: mediaCollision)

            #expect(throws: ManagedLibraryError.self) {
                try package.bootstrapForConfirmedImport()
            }
        }
    }

    private func withTemporaryDirectory(
        _ operation: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "CadenceManagedLibraryTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try operation(directory)
    }
}
