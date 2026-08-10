@testable import Cadence
import Testing

struct TrackTableColumnTests {
    @Test("Track tables default to Song, Album, Year, and Time")
    func defaultColumns() {
        #expect(
            TrackTableColumn.defaultVisible == [.album, .year, .time]
        )
        #expect(
            TrackTableColumn.decode(
                TrackTableColumn.defaultRawValue
            ) == [.album, .year, .time]
        )
    }

    @Test("Optional columns round trip in canonical display order")
    func columnPersistence() {
        let encoded = TrackTableColumn.encode(
            [
                .time,
                .year,
                .album,
            ]
        )

        #expect(
            TrackTableColumn.decode(encoded)
                == [.album, .year, .time]
        )
    }

    @Test("Existing installations receive the Year column once")
    func defaultMigration() {
        let migrated = TrackTableColumn.migrateDefaults(
            rawValue: TrackTableColumn.encode([.album, .time]),
            version: 0
        )

        #expect(
            TrackTableColumn.decode(migrated.rawValue)
                == [.album, .year, .time]
        )
        #expect(migrated.version == 2)
        #expect(
            TrackTableColumn.migrateDefaults(
                rawValue: TrackTableColumn.encode([.album]),
                version: 2
            ).rawValue == TrackTableColumn.encode([.album])
        )
    }
}
