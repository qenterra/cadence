import Foundation
import SwiftData

extension LibraryRepository {
    @discardableResult
    func createTag(
        displayPath: String
    ) throws -> UUID {
        let normalized = SearchNormalizer.normalize(displayPath)
        let components = displayPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        guard
            !normalized.isEmpty,
            components.count <= 2,
            components.allSatisfy({ !$0.isEmpty })
        else {
            throw ProductionTagEditError.invalidPath
        }

        let tag: TagRecord
        let predicate = #Predicate<TagRecord> {
            $0.normalizedPath == normalized
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            tag = existing
        } else {
            tag = TagRecord(
                displayPath: components.joined(separator: " / "),
                groupPath: components.count == 2 ? components[0] : nil
            )
            modelContext.insert(tag)
        }
        try modelContext.save()
        return tag.id
    }
}
