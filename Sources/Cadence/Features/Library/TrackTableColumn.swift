enum TrackTableColumn: String, CaseIterable, Identifiable, Codable, Sendable {
    case album
    case year
    case time

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .album: "Album"
        case .year: "Year"
        case .time: "Time"
        }
    }

    static let defaultVisible: [Self] = [.album, .year, .time]

    static var defaultRawValue: String {
        encode(defaultVisible)
    }

    static func decode(
        _ rawValue: String
    ) -> [Self] {
        let values = Set(
            rawValue
                .split(separator: ",")
                .compactMap { Self(rawValue: String($0)) }
        )
        return allCases.filter(values.contains)
    }

    static func encode(
        _ columns: some Sequence<Self>
    ) -> String {
        let values = Set(columns)
        return allCases
            .filter(values.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    static func migrateDefaults(
        rawValue: String,
        version: Int
    ) -> (rawValue: String, version: Int) {
        guard version < 2 else {
            return (rawValue, version)
        }
        var columns = Set(decode(rawValue))
        columns.insert(.year)
        return (encode(columns), 2)
    }
}
