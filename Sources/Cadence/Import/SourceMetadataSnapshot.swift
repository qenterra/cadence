import AVFoundation
import Foundation

struct SourceMetadataItem: Codable, Equatable, Sendable {
    let identifier: String?
    let rawKey: String
    let canonicalKey: String
    let keySpace: String?
    let localeIdentifier: String?
    let stringValue: String?
    let numberValue: Double?
    let dateValue: Date?
    let binaryByteCount: Int?
    let binaryContentHash: String?
    let dataType: String?
}

struct SourceMetadataSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let items: [SourceMetadataItem]

    init(
        version: Int = currentVersion,
        items: [SourceMetadataItem]
    ) {
        self.version = version
        self.items = items
    }

    static func capture(
        items: [AVMetadataItem]
    ) async throws -> SourceMetadataSnapshot {
        var captured: [SourceMetadataItem] = []
        captured.reserveCapacity(items.count)

        for item in items {
            let stringValue = try await item.load(.stringValue)
            let numberValue = try await item.load(.numberValue)
            let dateValue = try await item.load(.dateValue)
            let dataValue = try await item.load(.dataValue)
            let trimmedString = stringValue?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let binaryData = dataValue.flatMap { data in
                data.isEmpty ? nil : data
            }

            captured.append(
                SourceMetadataItem(
                    identifier: item.identifier?.rawValue,
                    rawKey: MetadataValueResolver.rawKey(of: item),
                    canonicalKey: MetadataValueResolver.canonicalKey(of: item),
                    keySpace: item.keySpace?.rawValue,
                    localeIdentifier: item.locale?.identifier,
                    stringValue: trimmedString?.isEmpty == false
                        ? trimmedString
                        : nil,
                    numberValue: numberValue?.doubleValue,
                    dateValue: dateValue,
                    binaryByteCount: binaryData?.count,
                    binaryContentHash: binaryData.map {
                        ContentHasher().sha256(of: $0)
                    },
                    dataType: item.dataType
                )
            )
        }

        return SourceMetadataSnapshot(items: captured)
    }
}
