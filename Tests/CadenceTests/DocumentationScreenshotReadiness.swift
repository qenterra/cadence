import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

// Readiness is an exhaustive scene matrix; keeping it in one switch makes any
// missing screenshot state fail visibly instead of falling through silently.
// swiftlint:disable cyclomatic_complexity function_body_length

@MainActor
extension DocumentationScreenshotFixture {
    var inferredScene: DocumentationScreenshotScene {
        if model.playbackWorkspace == .nowPlaying {
            return .nowPlaying
        }
        if model.selectedDestination == .albums,
           let albumID = model.selectedProductionAlbumID {
            return .album(albumID)
        }
        if model.selectedDestination == .artists,
           let artistID = model.selectedProductionArtistID {
            return .artist(artistID)
        }
        if model.selectedDestination == .smartCollections,
           model.smartCollectionsPresentationMode == .editing {
            return .smartCollectionEditor(
                isValid: model.smartCollectionValidation.isValid
            )
        }
        switch model.selectedDestination {
        case .home:
            return .home
        case .importMusic:
            return .importReview
        default:
            return .library(model.selectedDestination)
        }
    }

    func isReady(for scene: DocumentationScreenshotScene) -> Bool {
        guard model.librarySession.availability == .ready else {
            return false
        }
        switch scene {
        case .home:
            return model.selectedDestination == .home
                && model.librarySession.store.availability == .ready
        case let .library(destination):
            let destinationIsReady = if destination == .allTracks {
                model.librarySession.store.allTracksWindow?.firstPageState
                    == .ready
            } else if destination == .library {
                model.librarySession.store.browserAlbumsState == .ready
                    && model.librarySession.store.browserTracksState == .ready
                    && model.librarySession.store.browserAlbumID != nil
            } else if destination == .playlists {
                model.librarySession.store.playlistListState == .ready
                    && model.librarySession.store.selectedPlaylistTracksState
                    == .ready
            } else if destination == .smartCollections {
                smartCollectionListeningIsReady()
            } else {
                true
            }
            return model.playbackWorkspace == .hidden
                && model.selectedDestination == destination
                && destinationIsReady
        case let .album(albumID):
            return model.selectedProductionAlbumID == albumID
                && readinessTracker.isAlbumReady(albumID)
        case let .artist(artistID):
            return model.selectedProductionArtistID == artistID
                && readinessTracker.isArtistReady(artistID)
        case .nowPlaying:
            guard let trackID = model.currentPlaybackTrack?.id else {
                return false
            }
            return model.playbackWorkspace == .nowPlaying
                && readinessTracker.isNowPlayingReady(trackID)
        case .nowPlayingTagEntry:
            guard let trackID = model.currentPlaybackTrack?.id else {
                return false
            }
            return model.playbackWorkspace == .nowPlaying
                && readinessTracker.isNowPlayingReady(trackID)
        case let .smartCollectionEditor(isValid):
            let editorIsReady = model.selectedDestination == .smartCollections
                && model.smartCollectionsPresentationMode == .editing
                && model.smartCollectionDraft != nil
                && model.smartCollectionValidation.isValid == isValid
            guard editorIsReady, isValid else {
                return editorIsReady
            }
            return model.productionSmartCollectionLiveSummary.isEmpty
                || model.productionSmartCollectionLiveTrackSource != nil
        case .importReview:
            return model.selectedDestination == .importMusic
                && model.importPreviewStage == .review
                && !model.importCandidates.isEmpty
        case .settings:
            return true
        }
    }

    private func smartCollectionListeningIsReady() -> Bool {
        guard let rule = model.selectedSmartCollection?.rule else {
            return false
        }
        let expectedRules = Set(model.smartCollections.map(\.rule))
        let loadedRules = Set(
            model.librarySession.store.smartCollectionSummaries.keys
        )
        return model.librarySession.store.smartCollectionTrackSource(
            for: rule
        ) != nil && expectedRules.isSubset(of: loadedRules)
    }

    func readinessDiagnostic(
        for scene: DocumentationScreenshotScene
    ) -> String {
        switch scene {
        case .home:
            "destination=\(model.selectedDestination), "
                + "availability=\(model.librarySession.store.availability)"
        case let .album(albumID):
            "selected=\(String(describing: model.selectedProductionAlbumID)), "
                + readinessTracker.albumDiagnostic(albumID)
        case let .artist(artistID):
            "selected=\(String(describing: model.selectedProductionArtistID)), "
                + readinessTracker.artistDiagnostic(artistID)
        case .nowPlayingTagEntry:
            "workspace=\(model.playbackWorkspace), track="
                + "\(String(describing: model.currentPlaybackTrack?.id))"
        case let .smartCollectionEditor(isValid):
            "mode=\(model.smartCollectionsPresentationMode), expectedValid="
                + "\(isValid), actualValid=\(model.smartCollectionValidation.isValid)"
        case .library(.allTracks):
            "destination=\(model.selectedDestination), firstPage="
                + "\(String(describing: model.librarySession.store.allTracksWindow?.firstPageState))"
        case .library(.library):
            "destination=\(model.selectedDestination), albums="
                + "\(model.librarySession.store.browserAlbumsState), tracks="
                + "\(model.librarySession.store.browserTracksState), albumID="
                + "\(String(describing: model.librarySession.store.browserAlbumID))"
        case .library(.playlists):
            "destination=\(model.selectedDestination), playlists="
                + "\(model.librarySession.store.playlistListState), tracks="
                + "\(model.librarySession.store.selectedPlaylistTracksState)"
        case .library(.smartCollections):
            "destination=\(model.selectedDestination), selected="
                + "\(String(describing: model.selectedSmartCollectionID)), "
                + "tracksLoaded=\(model.selectedSmartCollectionTrackSource != nil), "
                + "summaries=\(model.librarySession.store.smartCollectionSummaries.count)"
        default:
            "destination=\(model.selectedDestination), workspace=\(model.playbackWorkspace)"
        }
    }

    static func trackedCatalogClient(
        repository: LibraryRepository,
        readinessTracker: DocumentationScreenshotReadinessTracker
    ) -> LibraryCatalogLookupClient {
        let base = LibraryCatalogLookupClient(repository: repository)
        return LibraryCatalogLookupClient(
            artist: { id in
                let artist = try await base.artist(id)
                await readinessTracker.didLoadArtist(id)
                return artist
            },
            album: { id in
                let album = try await base.album(id)
                await readinessTracker.didLoadAlbum(id)
                return album
            },
            albumTracks: { id in
                let tracks = try await base.albumTracks(id)
                await readinessTracker.didLoadAlbumTracks(id)
                return tracks
            },
            artistTracks: { id in
                let tracks = try await base.artistTracks(id)
                await readinessTracker.didLoadArtistTracks(id)
                return tracks
            },
            artistAlbums: base.artistAlbums,
            artistReleases: base.artistReleases,
            tagTracks: base.tagTracks,
            allTrackIDs: base.allTrackIDs
        )
    }

    func captureMatrix(prefix: String) async throws {
        for viewport in DocumentationScreenshotViewport.allCases {
            for appearance in DocumentationScreenshotAppearance.allCases {
                try await capture(
                    "qa-\(prefix)-\(viewport.slug)-\(appearance.slug).png",
                    contentSize: viewport.size,
                    appearance: appearance
                )
            }
        }
    }

    func captureSettingsMatrix(
        recordsOnly: Bool = false
    ) async throws {
        for tab in CadenceSettingsTab.allCases {
            for appearance in DocumentationScreenshotAppearance.allCases {
                try await captureSettings(
                    "qa-settings-\(tab.rawValue)-\(appearance.slug).png",
                    appearance: appearance,
                    tab: tab,
                    recordsOnly: recordsOnly
                )
            }
        }
    }

    static func storeScreenshot(
        _ data: Data,
        filename: String
    ) throws {
        if filename.hasPrefix("qa-all-tracks-") {
            Attachment.record([UInt8](data), named: filename)
        }

        let baseline = projectRoot.appending(path: "docs/images/\(filename)")
        let workspace = FileManager.default.temporaryDirectory.appending(
            path: "CadenceVisualRegression",
            directoryHint: .isDirectory
        )
        let marker = projectRoot.appending(path: ".build/update-screenshots")
        if FileManager.default.fileExists(atPath: marker.path) {
            // The hosted test app is sandboxed and cannot write into the
            // checkout. Emit a complete candidate set in its own container;
            // the developer-side update command promotes it after the run.
            let candidate = workspace.appending(path: "update/\(filename)")
            try FileManager.default.createDirectory(
                at: candidate.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: candidate, options: .atomic)
            return
        }

        let actual = workspace.appending(path: "actual/\(filename)")
        let diff = workspace.appending(path: "diff/\(filename)")
        try FileManager.default.createDirectory(
            at: actual.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: actual, options: .atomic)
        try DocumentationScreenshotComparator.assertMatch(
            actual: actual,
            baseline: baseline,
            diff: diff
        )
    }
}

// swiftlint:enable cyclomatic_complexity function_body_length
