@testable import Cadence
import Foundation
import Testing

@MainActor
struct CadenceStartupTests {
    @Test("Startup navigation restores only stable destinations")
    func startupNavigationPolicy() {
        #expect(
            StartupNavigationPolicy.resolve(
                startupPage: .home,
                lastDestinationRawValue: NavigationDestination.albums.rawValue
            ) == .home
        )
        #expect(
            StartupNavigationPolicy.resolve(
                startupPage: .tracks,
                lastDestinationRawValue: NavigationDestination.albums.rawValue
            ) == .allTracks
        )
        #expect(
            StartupNavigationPolicy.resolve(
                startupPage: .lastOpened,
                lastDestinationRawValue: NavigationDestination.albums.rawValue
            ) == .albums
        )
        #expect(
            StartupNavigationPolicy.resolve(
                startupPage: .lastOpened,
                lastDestinationRawValue: NavigationDestination.trash.rawValue
            ) == .home
        )
        #expect(StartupNavigationPolicy.shouldPersist(.playlists))
        #expect(!StartupNavigationPolicy.shouldPersist(.importMusic))
        #expect(!StartupNavigationPolicy.shouldPersist(.trash))
        #expect(
            StartupNavigationPolicy.shouldApply(
                currentDestination: .home,
                isPlaybackWorkspacePresented: false
            )
        )
        #expect(
            !StartupNavigationPolicy.shouldApply(
                currentDestination: .library,
                isPlaybackWorkspacePresented: false
            )
        )
        #expect(
            !StartupNavigationPolicy.shouldApply(
                currentDestination: .home,
                isPlaybackWorkspacePresented: true
            )
        )
    }

    @Test("Empty startup does not report unavailable persistent features")
    func emptyStartupIsQuiet() async throws {
        let musicDirectory = FileManager.default.temporaryDirectory.appending(
            path: "CadenceStartupTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: musicDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: musicDirectory)
        }
        let session = LibrarySession.startup(
            location: ManagedLibraryLocation(
                musicDirectory: musicDirectory
            )
        )
        let model = CadenceAppModel.production(
            librarySession: session
        )

        await model.loadInitialPersistentFeatures()

        #expect(session.availability == .empty)
        #expect(session.store.operationFailure == nil)
        #expect(session.store.playlistListState == .idle)
    }
}
