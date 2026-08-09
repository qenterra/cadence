enum TrackTableColumn: String, CaseIterable, Identifiable, Codable, Sendable {
    case album
    case year
    case dateAdded
    case playCount
    case time

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .album: "Album"
        case .year: "Year"
        case .dateAdded: "Date Added"
        case .playCount: "Plays"
        case .time: "Time"
        }
    }

    static let defaultVisible: [Self] = [.album, .time]

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
}
