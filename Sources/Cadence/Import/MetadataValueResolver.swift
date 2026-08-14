import AVFoundation
import Foundation

struct MetadataValueResolver {
    let items: [AVMetadataItem]

    func strings(
        commonIdentifier: AVMetadataIdentifier? = nil,
        rawKeys: Set<String>
    ) async throws -> [String] {
        var values: [String] = []
        for item in items {
            let matchesCommon = commonIdentifier.map {
                item.identifier == $0
            } ?? false
            let matchesRaw = rawKeys.contains(Self.canonicalKey(of: item))
            guard matchesCommon || matchesRaw,
                  let value = try await stringValue(of: item)
            else {
                continue
            }
            values.append(value)
        }
        return values
    }

    func string(
        commonIdentifier: AVMetadataIdentifier? = nil,
        rawKeys: Set<String>
    ) async throws -> String? {
        if let commonIdentifier {
            for item in items where item.identifier == commonIdentifier {
                if let value = try await stringValue(of: item) {
                    return value
                }
            }
        }

        for item in items where rawKeys.contains(Self.canonicalKey(of: item)) {
            if let value = try await stringValue(of: item) {
                return value
            }
        }
        return nil
    }

    func integer(
        rawKeys: Set<String>
    ) async throws -> Int? {
        guard let value = try await string(rawKeys: rawKeys) else {
            return nil
        }
        let firstComponent = value.split(separator: "/", maxSplits: 1).first
        guard let firstComponent else {
            return nil
        }
        return Int(
            firstComponent.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }

    func data(
        commonIdentifier: AVMetadataIdentifier? = nil,
        rawKeys: Set<String>
    ) async throws -> Data? {
        if let commonIdentifier {
            for item in items where item.identifier == commonIdentifier {
                if let value = try await item.load(.dataValue),
                   !value.isEmpty {
                    return value
                }
            }
        }
        for item in items where rawKeys.contains(Self.canonicalKey(of: item)) {
            if let value = try await item.load(.dataValue),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func stringValue(
        of item: AVMetadataItem
    ) async throws -> String? {
        guard let value = try await item.load(.stringValue) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    static func canonicalKey(
        of item: AVMetadataItem
    ) -> String {
        let rawKey = rawKey(of: item)
        return String(
            rawKey.uppercased().unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
            }
        )
    }

    static func rawKey(
        of item: AVMetadataItem
    ) -> String {
        item.identifier?.rawValue
            .split(separator: "/")
            .last
            .map(String.init)
            ?? (item.key as? String)
            ?? ""
    }
}
