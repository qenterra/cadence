@testable import Cadence
import Foundation
import Testing

struct SmartCollectionRepositoryTests {
    @Test("Smart Collections survive reopening, update in place, and delete durably")
    func durableCRUD() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "CadenceSmartCollectionRepositoryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = ManagedLibraryPackage(
            location: ManagedLibraryLocation(musicDirectory: directory)
        )
        try package.bootstrapForConfirmedImport()
        let id = UUID()
        let original = collection(id: id, name: "Favorites")

        do {
            let container = try LibraryContainerFactory.persistent(
                package: package
            )
            let repository = LibraryRepository(modelContainer: container)
            try await repository.saveSmartCollection(original)
        }

        do {
            let container = try LibraryContainerFactory.persistent(
                package: package
            )
            let repository = LibraryRepository(modelContainer: container)
            let reopened = try await repository.smartCollections()
            #expect(reopened == [original])

            var renamed = original
            renamed.name = "Loved Tracks"
            renamed.modifiedAt = Date(timeIntervalSince1970: 200)
            try await repository.saveSmartCollection(renamed)
            #expect(try await repository.smartCollections() == [renamed])

            try await repository.deleteSmartCollection(id: id)
            #expect(try await repository.smartCollections().isEmpty)
        }

        do {
            let container = try LibraryContainerFactory.persistent(
                package: package
            )
            let repository = LibraryRepository(modelContainer: container)
            #expect(try await repository.smartCollections().isEmpty)
        }
    }

    private func collection(
        id: UUID,
        name: String
    ) -> SmartCollectionPreview {
        SmartCollectionPreview(
            id: id,
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
