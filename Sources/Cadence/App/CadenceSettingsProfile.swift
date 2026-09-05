import Foundation

enum CadencePreferenceValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case double(Double)
    case integer(Int)
    case string(String)

    var propertyListValue: Any {
        switch self {
        case let .bool(value): value
        case let .double(value): value
        case let .integer(value): value
        case let .string(value): value
        }
    }
}

struct CadenceSettingsProfile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let preferences: [String: CadencePreferenceValue]
}

enum CadenceSettingsProfileError: LocalizedError, Equatable {
    case invalidValue(String)
    case unreadable
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case let .invalidValue(key):
            String(localized: "The value for “\(key)” is not valid.")
        case .unreadable:
            String(localized: "The settings file could not be read.")
        case let .unsupportedSchema(version):
            String(localized: "Settings format version \(version) is not supported.")
        }
    }
}

@MainActor
final class CadenceSettingsProfileService {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        CadencePreferences.registerDefaults(in: defaults)
    }

    func makeProfile() -> CadenceSettingsProfile {
        let values = CadencePreferences.portableDescriptors.reduce(
            into: [String: CadencePreferenceValue]()
        ) { result, descriptor in
            result[descriptor.key] = descriptor.currentValue(in: defaults)
        }
        return CadenceSettingsProfile(
            schemaVersion: CadenceSettingsProfile.currentSchemaVersion,
            preferences: values
        )
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makeProfile())
    }

    func importData(_ data: Data) throws {
        let profile: CadenceSettingsProfile
        do {
            profile = try JSONDecoder().decode(
                CadenceSettingsProfile.self,
                from: data
            )
        } catch {
            throw CadenceSettingsProfileError.unreadable
        }
        try importProfile(profile)
    }

    func importProfile(_ profile: CadenceSettingsProfile) throws {
        guard
            profile.schemaVersion == CadenceSettingsProfile.currentSchemaVersion
        else {
            throw CadenceSettingsProfileError.unsupportedSchema(
                profile.schemaVersion
            )
        }

        let descriptors = Dictionary(
            uniqueKeysWithValues: CadencePreferences.portableDescriptors.map {
                ($0.key, $0)
            }
        )
        var validated: [(String, CadencePreferenceValue)] = []
        for (key, value) in profile.preferences {
            guard let descriptor = descriptors[key] else {
                continue
            }
            guard descriptor.accepts(value) else {
                throw CadenceSettingsProfileError.invalidValue(key)
            }
            validated.append((key, value))
        }

        for (key, value) in validated {
            defaults.set(value.propertyListValue, forKey: key)
        }
    }

    func resetCustomization() {
        for descriptor in CadencePreferences.resettableDescriptors {
            defaults.removeObject(forKey: descriptor.key)
        }
        CadencePreferences.registerDefaults(in: defaults)
    }
}

struct CadencePreferenceDescriptor {
    enum Validation {
        case bool
        case double(ClosedRange<Double>?)
        case integer(Set<Int>?)
        case string(Set<String>?)
    }

    let key: String
    let defaultValue: CadencePreferenceValue
    let validation: Validation
    let isPortable: Bool
    let isResettable: Bool

    static func bool(
        _ key: String,
        default value: Bool,
        portable: Bool = true,
        resettable: Bool = true
    ) -> Self {
        Self(
            key: key,
            defaultValue: .bool(value),
            validation: .bool,
            isPortable: portable,
            isResettable: resettable
        )
    }

    static func double(
        _ key: String,
        default value: Double,
        range: ClosedRange<Double>? = nil,
        portable: Bool = true,
        resettable: Bool = true
    ) -> Self {
        Self(
            key: key,
            defaultValue: .double(value),
            validation: .double(range),
            isPortable: portable,
            isResettable: resettable
        )
    }

    static func integer(
        _ key: String,
        default value: Int,
        allowed: Set<Int>? = nil,
        portable: Bool = true,
        resettable: Bool = true
    ) -> Self {
        Self(
            key: key,
            defaultValue: .integer(value),
            validation: .integer(allowed),
            isPortable: portable,
            isResettable: resettable
        )
    }

    static func string(
        _ key: String,
        default value: String,
        allowed: Set<String>? = nil,
        portable: Bool = true,
        resettable: Bool = true
    ) -> Self {
        Self(
            key: key,
            defaultValue: .string(value),
            validation: .string(allowed),
            isPortable: portable,
            isResettable: resettable
        )
    }

    func accepts(_ value: CadencePreferenceValue) -> Bool {
        switch (validation, value) {
        case (.bool, .bool):
            true
        case let (.double(range), .double(value)):
            value.isFinite && (range?.contains(value) ?? true)
        case let (.integer(allowed), .integer(value)):
            allowed?.contains(value) ?? true
        case let (.string(allowed), .string(value)):
            allowed?.contains(value) ?? true
        default:
            false
        }
    }

    func currentValue(in defaults: UserDefaults) -> CadencePreferenceValue {
        guard let object = defaults.object(forKey: key) else {
            return defaultValue
        }
        let candidate: CadencePreferenceValue? = switch validation {
        case .bool:
            (object as? Bool).map(CadencePreferenceValue.bool)
        case .double:
            (object as? NSNumber).map {
                CadencePreferenceValue.double($0.doubleValue)
            }
        case .integer:
            (object as? NSNumber).map {
                CadencePreferenceValue.integer($0.intValue)
            }
        case .string:
            (object as? String).map(CadencePreferenceValue.string)
        }
        guard let candidate, accepts(candidate) else {
            return defaultValue
        }
        return candidate
    }
}
