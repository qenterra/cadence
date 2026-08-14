import AppKit
@testable import Cadence
import Foundation
import SwiftData
import SwiftUI
import Testing

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
        case let .library(destination):
            let destinationIsReady = if destination == .allTracks {
                model.librarySession.store.allTracksWindow?.firstPageState
                    == .ready
            } else {
                true
            }
            return model.playbackWorkspace == .hidden
                && model.selectedDestination == destination
                && destinationIsReady
        case let .album(albumID):
            return model.selectedProductionAlbumID == albumID
                && readinessTracker.isAlbumReady(albumID)
        case .nowPlaying:
            return model.playbackWorkspace == .nowPlaying
                && model.currentPlaybackTrack != nil
        case .importReview:
            return model.selectedDestination == .importMusic
                && model.importPreviewStage == .review
                && !model.importCandidates.isEmpty
        case .settings:
            return true
        }
    }

    func readinessDiagnostic(
        for scene: DocumentationScreenshotScene
    ) -> String {
        switch scene {
        case .home:
            "destination=\(model.selectedDestination)"
        case let .album(albumID):
            "selected=\(String(describing: model.selectedProductionAlbumID)), "
                + readinessTracker.albumDiagnostic(albumID)
        case .library(.allTracks):
            "destination=\(model.selectedDestination), firstPage="
                + "\(String(describing: model.librarySession.store.allTracksWindow?.firstPageState))"
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
            artist: base.artist,
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
            artistTracks: base.artistTracks,
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

    func captureSettingsMatrix() async throws {
        for tab in CadenceSettingsTab.allCases {
            for appearance in DocumentationScreenshotAppearance.allCases {
                try await captureSettings(
                    "qa-settings-\(tab.rawValue)-\(appearance.slug).png",
                    appearance: appearance,
                    tab: tab
                )
            }
        }
    }

    static func storeScreenshot(
        _ data: Data,
        filename: String
    ) throws {
        let baseline = projectRoot.appending(path: "docs/images/\(filename)")
        let workspace = FileManager.default.temporaryDirectory.appending(
            path: "CadenceVisualRegression",
            directoryHint: .isDirectory
        )
        let marker = projectRoot.appending(path: ".build/update-screenshots")
        if FileManager.default.fileExists(atPath: marker.path) {
            try data.write(to: baseline, options: .atomic)
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
