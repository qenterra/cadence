enum LibraryPageBuilder {
    static func page<Record, Projection: Sendable>(
        records: [Record],
        limit: Int,
        sortValue: KeyPath<Record, String>,
        identity: KeyPath<Record, String>,
        projection: (Record) -> Projection
    ) -> LibraryPage<Projection> {
        let hasMore = records.count > limit
        let pageRecords = Array(records.prefix(limit))
        let nextCursor = hasMore
            ? pageRecords.last.map {
                LibraryPageCursor(
                    sortValue: $0[keyPath: sortValue],
                    identity: $0[keyPath: identity]
                )
            }
            : nil

        return LibraryPage(
            items: pageRecords.map(projection),
            nextCursor: nextCursor
        )
    }
}
