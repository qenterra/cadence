import Foundation

extension LibraryStore {
    func persistedSmartCollections() async -> [SmartCollectionPreview]? {
        do {
            let repository = try requireRepository()
            return try await repository.smartCollections()
        } catch {
            recordOperationFailure(.smartCollections, error: error)
            return nil
        }
    }

    func savePersistedSmartCollection(
        _ collection: SmartCollectionPreview
    ) async -> Bool {
        do {
            let repository = try requireRepository()
            try await repository.saveSmartCollection(collection)
            return true
        } catch {
            recordOperationFailure(.smartCollections, error: error)
            return false
        }
    }

    func deletePersistedSmartCollection(id: UUID) async -> Bool {
        do {
            let repository = try requireRepository()
            try await repository.deleteSmartCollection(id: id)
            return true
        } catch {
            recordOperationFailure(.smartCollections, error: error)
            return false
        }
    }

    func loadSmartCollectionRuleData() async {
        smartCollectionRuleDataGeneration &+= 1
        let generation = smartCollectionRuleDataGeneration
        isLoadingSmartCollectionData = true
        defer {
            isLoadingSmartCollectionData = false
        }
        do {
            let repository = try requireRepository()
            let data = try await repository
                .productionSmartCollectionRuleData()
            guard generation == smartCollectionRuleDataGeneration else {
                return
            }
            smartCollectionRuleData = data
        } catch {
            guard generation == smartCollectionRuleDataGeneration else {
                return
            }
            recordOperationFailure(.smartCollections, error: error)
        }
    }

    func loadSmartCollectionSummaries(
        rules: [SmartCollectionRuleGroup]
    ) async {
        smartCollectionSummaryGeneration &+= 1
        let generation = smartCollectionSummaryGeneration
        var summaries: [
            SmartCollectionRuleGroup: ProductionSmartCollectionSummary
        ] = [:]
        do {
            let repository = try requireRepository()
            for rule in Set(rules) {
                let evaluation = try await repository
                    .evaluateProductionSmartCollection(root: rule)
                guard generation == smartCollectionSummaryGeneration else {
                    return
                }
                summaries[rule] = ProductionSmartCollectionSummary(
                    count: evaluation.count,
                    totalDuration: evaluation.totalDuration
                )
            }
        } catch {
            recordOperationFailure(.smartCollections, error: error)
            return
        }
        smartCollectionSummaries = summaries
    }

    func loadSmartCollectionResult(
        rule: SmartCollectionRuleGroup
    ) async {
        smartCollectionResultGeneration &+= 1
        let generation = smartCollectionResultGeneration
        do {
            let repository = try requireRepository()
            let evaluation = try await repository
                .evaluateProductionSmartCollection(root: rule)
            let page = try await repository
                .productionSmartCollectionTrackPage(
                    orderedIDs: evaluation.orderedTrackIDs
                )
            guard generation == smartCollectionResultGeneration else {
                return
            }
            smartCollectionSummaries[rule] = ProductionSmartCollectionSummary(
                count: evaluation.count,
                totalDuration: evaluation.totalDuration
            )
            smartCollectionResults = [
                rule: ProductionSmartCollectionStoreResult(
                    evaluation: evaluation,
                    tracks: page.items,
                    nextOffset: page.nextOffset,
                    contentVersion: TrackTableContentVersion(
                        sourceID: UUID(),
                        generation: 0
                    )
                ),
            ]
        } catch {
            guard generation == smartCollectionResultGeneration else {
                return
            }
            recordOperationFailure(.smartCollections, error: error)
        }
    }

    func loadNextSmartCollectionResult(
        rule: SmartCollectionRuleGroup
    ) async {
        guard
            !isLoadingNextSmartCollectionResult,
            var result = smartCollectionResults[rule],
            let offset = result.nextOffset
        else {
            return
        }
        isLoadingNextSmartCollectionResult = true
        let generation = smartCollectionResultGeneration
        defer {
            isLoadingNextSmartCollectionResult = false
        }
        do {
            let repository = try requireRepository()
            let page = try await repository
                .productionSmartCollectionTrackPage(
                    orderedIDs: result.evaluation.orderedTrackIDs,
                    offset: offset
                )
            guard generation == smartCollectionResultGeneration else {
                return
            }
            let existingIDs = Set(result.tracks.map(\.id))
            let additions = page.items.filter {
                !existingIDs.contains($0.id)
            }
            if !additions.isEmpty {
                result.tracks.append(contentsOf: additions)
                result.contentVersion = result.contentVersion.advanced()
            }
            result.nextOffset = page.nextOffset
            smartCollectionResults[rule] = result
        } catch {
            recordOperationFailure(.smartCollections, error: error)
        }
    }

    func smartCollectionSummary(
        for rule: SmartCollectionRuleGroup
    ) -> ProductionSmartCollectionSummary {
        smartCollectionSummaries[rule] ?? .empty
    }

    func smartCollectionTracks(
        for rule: SmartCollectionRuleGroup
    ) -> [LibraryTrackProjection] {
        smartCollectionResults[rule]?.tracks ?? []
    }

    func smartCollectionTrackSource(
        for rule: SmartCollectionRuleGroup
    ) -> ProductionTrackTableSource? {
        guard let result = smartCollectionResults[rule] else {
            return nil
        }
        return ProductionTrackTableSource(
            tracks: result.tracks,
            contentVersion: result.contentVersion
        )
    }

    func completeSmartCollectionTracks(
        for rule: SmartCollectionRuleGroup
    ) async -> [LibraryTrackProjection] {
        do {
            let repository = try requireRepository()
            let evaluation = try await repository
                .evaluateProductionSmartCollection(root: rule)
            return try await completeSmartCollectionTracks(
                evaluation: evaluation,
                repository: repository
            )
        } catch {
            recordOperationFailure(.smartCollections, error: error)
            return []
        }
    }

    private func completeSmartCollectionTracks(
        evaluation: ProductionSmartCollectionEvaluation,
        repository: LibraryRepository
    ) async throws -> [LibraryTrackProjection] {
        var tracks: [LibraryTrackProjection] = []
        var offset = 0
        while offset < evaluation.count {
            let page = try await repository.productionSmartCollectionTrackPage(
                orderedIDs: evaluation.orderedTrackIDs,
                offset: offset
            )
            tracks.append(contentsOf: page.items)
            guard let nextOffset = page.nextOffset else {
                break
            }
            offset = nextOffset
        }
        return tracks
    }
}
