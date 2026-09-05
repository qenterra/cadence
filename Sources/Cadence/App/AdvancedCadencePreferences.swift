import Foundation
import SwiftUI

enum InterfaceTextSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small
    case standard
    case large

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .standard: String(localized: "Standard")
        case .large: String(localized: "Large")
        }
    }

    var nativePrimaryPointSize: CGFloat {
        switch self {
        case .small: 12
        case .standard: 13
        case .large: 15
        }
    }

    var nativeSecondaryPointSize: CGFloat {
        switch self {
        case .small: 11
        case .standard: 13
        case .large: 14
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: .small
        case .standard: .medium
        case .large: .large
        }
    }
}

enum TrackTableDensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact
    case standard
    case comfortable

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .standard: String(localized: "Standard")
        case .comfortable: String(localized: "Comfortable")
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .compact: 50
        case .standard: 58
        case .comfortable: 68
        }
    }

    var headerHeight: CGFloat {
        switch self {
        case .compact: 34
        case .standard: 38
        case .comfortable: 42
        }
    }

    var artworkSize: CGFloat {
        switch self {
        case .compact: 34
        case .standard: 40
        case .comfortable: 48
        }
    }
}

enum StartupPage: String, CaseIterable, Codable, Identifiable, Sendable {
    case home
    case lastOpened
    case tracks

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .lastOpened: String(localized: "Last Opened")
        case .tracks: String(localized: "Tracks")
        }
    }
}

enum VolumeAdjustmentStep: Int, CaseIterable, Codable, Identifiable, Sendable {
    case percent2 = 2
    case percent5 = 5
    case percent10 = 10

    var id: Self {
        self
    }

    var delta: Double {
        Double(rawValue) / 100
    }

    var title: String {
        "\(rawValue)%"
    }
}

enum CrossfadeDuration: Int, CaseIterable, Codable, Identifiable, Sendable {
    case off = 0
    case seconds2 = 2
    case seconds4 = 4
    case seconds6 = 6
    case seconds8 = 8
    case seconds12 = 12

    var id: Self {
        self
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .seconds2: String(localized: "2 seconds")
        case .seconds4: String(localized: "4 seconds")
        case .seconds6: String(localized: "6 seconds")
        case .seconds8: String(localized: "8 seconds")
        case .seconds12: String(localized: "12 seconds")
        }
    }
}

enum ListeningHistoryRetention: Int, CaseIterable, Codable, Identifiable,
    Sendable {
    case forever = 0
    case days30 = 30
    case days90 = 90
    case oneYear = 365

    var id: Self {
        self
    }

    var dayCount: Int? {
        self == .forever ? nil : rawValue
    }

    var title: String {
        switch self {
        case .forever: String(localized: "Forever")
        case .days30: String(localized: "30 Days")
        case .days90: String(localized: "90 Days")
        case .oneYear: String(localized: "1 Year")
        }
    }

    func cutoffDate(
        relativeTo now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        dayCount.flatMap {
            calendar.date(byAdding: .day, value: -$0, to: now)
        }
    }
}

enum TrashCleanupRetention: Int, CaseIterable, Codable, Identifiable,
    Sendable {
    case never = 0
    case days30 = 30
    case days90 = 90
    case oneYear = 365

    var id: Self {
        self
    }

    var dayCount: Int? {
        self == .never ? nil : rawValue
    }

    var title: String {
        switch self {
        case .never: String(localized: "Never")
        case .days30: String(localized: "After 30 Days")
        case .days90: String(localized: "After 90 Days")
        case .oneYear: String(localized: "After 1 Year")
        }
    }

    func cutoffDate(
        relativeTo now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        dayCount.flatMap {
            calendar.date(byAdding: .day, value: -$0, to: now)
        }
    }
}

extension CadencePreferences {
    static func interfaceTextSize(
        in defaults: UserDefaults = .standard
    ) -> InterfaceTextSize {
        repairedStringEnum(
            InterfaceTextSize.self,
            key: Keys.interfaceTextSize,
            fallback: .standard,
            defaults: defaults
        )
    }

    static func trackTableDensity(
        in defaults: UserDefaults = .standard
    ) -> TrackTableDensity {
        repairedStringEnum(
            TrackTableDensity.self,
            key: Keys.trackTableDensity,
            fallback: .standard,
            defaults: defaults
        )
    }

    static func startupPage(
        in defaults: UserDefaults = .standard
    ) -> StartupPage {
        repairedStringEnum(
            StartupPage.self,
            key: Keys.startupPage,
            fallback: .home,
            defaults: defaults
        )
    }

    static func volumeAdjustmentStep(
        in defaults: UserDefaults = .standard
    ) -> VolumeAdjustmentStep {
        repairedIntegerEnum(
            VolumeAdjustmentStep.self,
            key: Keys.volumeAdjustmentStep,
            fallback: .percent5,
            defaults: defaults
        )
    }

    static func crossfadeDuration(
        in defaults: UserDefaults = .standard
    ) -> CrossfadeDuration {
        repairedIntegerEnum(
            CrossfadeDuration.self,
            key: Keys.crossfadeDuration,
            fallback: .off,
            defaults: defaults
        )
    }

    static func listeningHistoryRetention(
        in defaults: UserDefaults = .standard
    ) -> ListeningHistoryRetention {
        repairedIntegerEnum(
            ListeningHistoryRetention.self,
            key: Keys.listeningHistoryRetention,
            fallback: .forever,
            defaults: defaults
        )
    }

    static func trashCleanupRetention(
        in defaults: UserDefaults = .standard
    ) -> TrashCleanupRetention {
        repairedIntegerEnum(
            TrashCleanupRetention.self,
            key: Keys.trashCleanupRetention,
            fallback: .never,
            defaults: defaults
        )
    }
}

enum TrackTablePreferences {
    static func reset(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: CadencePreferences.Keys.showsTrackArtwork)
        defaults.set(
            TrackTableDensity.standard.rawValue,
            forKey: CadencePreferences.Keys.trackTableDensity
        )
        defaults.set(
            TrackTableColumn.defaultRawValue,
            forKey: "trackTable.visibleColumns"
        )
        defaults.set(2, forKey: "trackTable.columnDefaultsVersion")
        defaults.set(
            TrackTableSortField.song.rawValue,
            forKey: "trackTable.sortField"
        )
        defaults.set(
            TrackTableSortDirection.ascending.rawValue,
            forKey: "trackTable.sortDirection"
        )
    }
}
