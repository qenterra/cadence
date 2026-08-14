import Foundation

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
    }
}
