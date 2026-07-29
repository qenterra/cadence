@testable import Cadence
import Testing

struct SmartCollectionTrackTableTests {
    @Test("Track tables default to Song, Album, and Time")
    func defaultColumns() {
        #expect(
            TrackTableColumn.defaultVisible == [.album, .time]
        )
        #expect(
            TrackTableColumn.decode(
                TrackTableColumn.defaultRawValue
            ) == [.album, .time]
        )
    }

    @Test("Optional columns round trip in canonical display order")
    func columnPersistence() {
        let encoded = TrackTableColumn.encode(
            [
                .time,
                .year,
                .album,
                .dateAdded,
                .playCount,
            ]
        )

        #expect(
            TrackTableColumn.decode(encoded)
                == [.album, .year, .dateAdded, .playCount, .time]
        )
    }
}
