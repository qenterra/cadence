import Foundation

enum StartupNavigationPolicy {
    private static let persistentDestinations: Set<NavigationDestination> = [
        .home,
        .library,
        .allTracks,
        .albums,
        .artists,
        .favorites,
        .tags,
        .smartCollections,
        .playlists,
    ]

    static func resolve(
        startupPage: StartupPage,
        lastDestinationRawValue: String
    ) -> NavigationDestination {
        switch startupPage {
        case .home:
            .home
        case .tracks:
            .allTracks
        case .lastOpened:
            if let destination = NavigationDestination(
                rawValue: lastDestinationRawValue
            ), shouldPersist(destination) {
                destination
            } else {
                .home
            }
        }
    }

    static func shouldPersist(_ destination: NavigationDestination) -> Bool {
        persistentDestinations.contains(destination)
    }

    /// Applies the launch preference only while the root still owns its
    /// untouched initial navigation state. Deep links, restored playback
    /// workspaces, and deterministic preview scenes already express a newer
    /// navigation intent and must win over the launch default.
    static func shouldApply(
        currentDestination: NavigationDestination,
        isPlaybackWorkspacePresented: Bool
    ) -> Bool {
        currentDestination == .home && !isPlaybackWorkspacePresented
    }
}

extension CadenceAppModel {
    /// Loads features that are meaningful only after a managed library exists.
    ///
    /// A first launch deliberately has no repository. Treating that expected
    /// state as a storage failure would show recovery alerts before the user
    /// has chosen any music to import.
    func loadInitialPersistentFeatures() async {
        guard librarySession.availability == .ready else {
            return
        }

        if librarySession.store.tracks.isEmpty {
            await librarySession.store.loadInitialLibrary()
        }
        guard librarySession.store.availability == .ready else {
            return
        }

        await loadPersistedSmartCollections()
        await librarySession.store.loadPlaylists()
        await restorePlaybackSessionIfNeeded()
        await runConfiguredLibraryMaintenance()
    }

    func runConfiguredLibraryMaintenance(
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) async {
        guard runtimeMode == .production,
              librarySession.availability == .ready else {
            return
        }
        do {
            if let cutoff = CadencePreferences.listeningHistoryRetention(in: defaults)
                .cutoffDate(relativeTo: now, calendar: calendar) {
                try await librarySession.store.pruneListeningHistory(
                    olderThan: cutoff
                )
            }
            if let cutoff = CadencePreferences.trashCleanupRetention(in: defaults)
                .cutoffDate(relativeTo: now, calendar: calendar) {
                try await librarySession.store.emptyExpiredTrash(
                    olderThan: cutoff,
                    location: librarySession.location
                )
            }
        } catch is CancellationError {
            return
        } catch {
            publishOperationError(error, on: .libraryOperation)
        }
    }
}
