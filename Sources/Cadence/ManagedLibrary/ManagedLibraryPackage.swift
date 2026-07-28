import Foundation

struct ManagedLibraryPackage: Sendable {
    private static let supportedAudioExtensions: Set<String> = [
        "aac",
        "aif",
        "aiff",
        "flac",
        "m4a",
        "mp3",
        "wav",
    ]

    let location: ManagedLibraryLocation

    var packageURL: URL {
        location.packageURL
    }

    var mediaDirectoryURL: URL {
        directoryURL("Media")
    }

    var lyricsDirectoryURL: URL {
        directoryURL("Lyrics")
    }

    var artworkDirectoryURL: URL {
        directoryURL("Artwork")
    }

    var artworkOriginalDirectoryURL: URL {
        directoryURL("Artwork/Original")
    }

    var artworkThumbnailsDirectoryURL: URL {
        directoryURL("Artwork/Thumbnails")
    }

    var metadataDirectoryURL: URL {
        directoryURL("Metadata")
    }

    var metadataStoreURL: URL {
        metadataDirectoryURL.appending(
            path: "Library.store",
            directoryHint: .notDirectory
        )
    }

    var stagingDirectoryURL: URL {
        directoryURL("Staging")
    }

    var trashDirectoryURL: URL {
        directoryURL("Trash")
    }

    func mediaURL(
        trackID: UUID,
        originalExtension: String
    ) throws -> URL {
        let normalizedExtension = originalExtension.lowercased()
        guard Self.supportedAudioExtensions.contains(normalizedExtension) else {
            throw ManagedLibraryError.unsupportedAudioFileExtension(
                originalExtension
            )
        }

        return mediaDirectoryURL.appending(
            path: "\(trackID.uuidString).\(normalizedExtension)",
            directoryHint: .notDirectory
        )
    }

    func lyricURL(trackID: UUID) -> URL {
        lyricsDirectoryURL.appending(
            path: "\(trackID.uuidString).lrc",
            directoryHint: .notDirectory
        )
    }

    func stagingURL(importID: UUID) -> URL {
        stagingDirectoryURL.appending(
            path: importID.uuidString,
            directoryHint: .isDirectory
        )
    }

    func bootstrapForConfirmedImport(
        fileManager: FileManager = .default
    ) throws {
        for directory in requiredDirectories {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: directory.path,
                isDirectory: &isDirectory
            ) {
                guard isDirectory.boolValue else {
                    throw ManagedLibraryError.layoutCollision(directory.path)
                }
                continue
            }

            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    private var requiredDirectories: [URL] {
        [
            packageURL,
            mediaDirectoryURL,
            lyricsDirectoryURL,
            artworkOriginalDirectoryURL,
            artworkThumbnailsDirectoryURL,
            metadataDirectoryURL,
            stagingDirectoryURL,
            trashDirectoryURL,
        ]
    }

    private func directoryURL(_ relativePath: String) -> URL {
        packageURL.appending(
            path: relativePath,
            directoryHint: .isDirectory
        )
    }
}
