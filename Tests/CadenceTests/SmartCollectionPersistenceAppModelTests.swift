@testable import Cadence
import Foundation
import Testing

@MainActor
struct SmartCollectionPersistenceAppModelTests {
    @Test("Production model loads, saves, and deletes Smart Collections through the managed store")
    func productionLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "CadenceSmartCollectionAppModelTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let location = ManagedLibraryLocation(musicDirectory: directory)
        let package = ManagedLibraryPackage(location: location)
        try package.bootstrapForConfirmedImport()
        try package.writeIdentity(LibraryIdentity())
        let original = collection(name: "Favorites")
        let container = try LibraryContainerFactory.persistent(package: package)
        let repository = LibraryRepository(modelContainer: container)
        try await repository.saveSmartCollection(original)

        let model = CadenceAppModel.production(
            librarySession: .startup(location: location)
        )
        await model.loadPersistedSmartCollections()
        #expect(model.smartCollections == [original])
        #expect(model.selectedSmartCollectionID == original.id)

        #expect(model.requestEditSelectedSmartCollection())
        model.renameSmartCollectionDraft("Loved Tracks")
        #expect(
            await model.saveSmartCollectionDraftPersisting(
                modifiedAt: Date(timeIntervalSince1970: 200)
            )
        )
        #expect(try await repository.smartCollections().first?.name == "Loved Tracks")

        model.requestDeleteSmartCollection(original.id)
        #expect(await model.confirmDeleteSmartCollectionPersisting())
        #expect(model.smartCollections.isEmpty)
        #expect(try await repository.smartCollections().isEmpty)
    }

    private func collection(name: String) -> SmartCollectionPreview {
        SmartCollectionPreview(
            name: name,
            rule: SmartCollectionRuleGroup(
                combinator: .all,
                children: [
                    .condition(
                        SmartCollectionRuleCondition(
                            field: .favorite,
                            operator: .is,
                            value: .boolean(true)
                        )
                    ),
                ]
            ),
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
