import Foundation

struct ManagedAudioMetadataEdit: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let year: Int?

    var normalized: Self {
        Self(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.trimmingCharacters(in: .whitespacesAndNewlines),
            year: year
        )
    }
}

enum ManagedAudioMetadataEditError: Error, LocalizedError, Sendable {
    case invalidField(String)
    case malformedContainer(String)
    case unsupportedContainer(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidField(field):
            "The \(field) field cannot be empty."
        case let .malformedContainer(format):
            "The \(format) metadata container is malformed. The original file was not changed."
        case let .unsupportedContainer(format):
            "Cadence cannot safely edit tags in this \(format) file."
        case let .verificationFailed(filename):
            "Cadence could not verify the new tags in \(filename). The original file was not changed."
        }
    }
}

struct ManagedAudioMetadataEditor {
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
    }

    func write(
        _ requestedEdit: ManagedAudioMetadataEdit,
        to url: URL
    ) async throws {
        let edit = requestedEdit.normalized
        guard !edit.title.isEmpty else {
            throw ManagedAudioMetadataEditError.invalidField("title")
        }
        guard !edit.artist.isEmpty else {
            throw ManagedAudioMetadataEditError.invalidField("artist")
        }
        guard !edit.album.isEmpty else {
            throw ManagedAudioMetadataEditError.invalidField("album")
        }
        if let year = edit.year, !(0 ... 9999).contains(year) {
            throw ManagedAudioMetadataEditError.invalidField("year")
        }

        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        let rewritten = try AudioMetadataContainerEditor.rewrite(
            original,
            fileExtension: url.pathExtension,
            edit: edit
        )
        let temporaryBasename = url.deletingPathExtension().lastPathComponent
        let temporaryFilename = ".\(temporaryBasename).cadence-tags-\(UUID().uuidString).\(url.pathExtension)"
        let temporaryURL = url.deletingLastPathComponent().appending(
            path: temporaryFilename,
            directoryHint: .notDirectory
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try rewritten.write(to: temporaryURL, options: .atomic)
        let onDisk = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        let verified = try AudioMetadataContainerEditor.rewrite(
            onDisk,
            fileExtension: url.pathExtension,
            edit: edit
        )
        guard onDisk == rewritten, verified == rewritten else {
            throw ManagedAudioMetadataEditError.verificationFailed(
                url.lastPathComponent
            )
        }

        _ = try fileManager.replaceItemAt(
            url,
            withItemAt: temporaryURL,
            backupItemName: nil,
            options: []
        )
    }
}

enum AudioMetadataContainerEditor {
    static func rewrite(
        _ data: Data,
        fileExtension: String,
        edit: ManagedAudioMetadataEdit
    ) throws -> Data {
        switch fileExtension.lowercased() {
        case "aac", "mp3":
            try ID3Editor.rewrite(data, edit: edit)
        case "flac":
            try FLACCommentEditor.rewrite(data, edit: edit)
        case "wav", "wave":
            try RIFFInfoEditor.rewrite(data, edit: edit)
        case "aif", "aiff", "aifc":
            try AIFFMetadataEditor.rewrite(data, edit: edit)
        case "m4a", "mp4":
            try MP4MetadataEditor.rewrite(data, edit: edit)
        default:
            throw ManagedAudioMetadataEditError.unsupportedContainer(
                fileExtension.uppercased()
            )
        }
    }
}

enum ID3Editor {
    static func rewrite(
        _ data: Data,
        edit: ManagedAudioMetadataEdit
    ) throws -> Data {
        var version = 4
        var audioOffset = 0
        var preservedFrames: [Data] = []

        if data.count >= 10, data.prefix(3) == Data("ID3".utf8) {
            version = Int(data[3])
            guard [2, 3, 4].contains(version), data[5] & 0x80 == 0 else {
                throw ManagedAudioMetadataEditError.unsupportedContainer("ID3")
            }
            let tagSize = try synchsafe(data, at: 6)
            audioOffset = 10 + tagSize + (data[5] & 0x10 == 0 ? 0 : 10)
            guard audioOffset <= data.count else {
                throw ManagedAudioMetadataEditError.malformedContainer("ID3")
            }
            preservedFrames = try frames(
                in: data.subdata(in: 10 ..< 10 + tagSize),
                version: version
            ).filter { frame in
                !targetFrameIDs(version: version).contains(frame.id)
            }.map(\.raw)
        }

        let yearFrameID = switch version {
        case 2: "TYE"
        case 3: "TYER"
        default: "TDRC"
        }
        let values: [(String, String)] = [
            (version == 2 ? "TT2" : "TIT2", edit.title),
            (version == 2 ? "TP1" : "TPE1", edit.artist),
            (version == 2 ? "TAL" : "TALB", edit.album),
            (yearFrameID, edit.year.map(String.init) ?? ""),
        ]
        let payload = preservedFrames.reduce(into: Data()) { $0.append($1) }
            + values.filter { !$0.1.isEmpty }.reduce(into: Data()) {
                $0.append(textFrame(id: $1.0, value: $1.1, version: version))
            }
        var header = Data("ID3".utf8)
        header.append(UInt8(version))
        header.append(0)
        header.append(0)
        header.append(contentsOf: synchsafeBytes(payload.count))
        return header + payload + data.suffix(from: audioOffset)
    }

    private struct Frame {
        let id: String
        let raw: Data
    }

    private static func frames(in data: Data, version: Int) throws -> [Frame] {
        var result: [Frame] = []
        var offset = 0
        let headerSize = version == 2 ? 6 : 10
        while offset + headerSize <= data.count {
            let idLength = version == 2 ? 3 : 4
            let idData = data.subdata(in: offset ..< offset + idLength)
            if idData.allSatisfy({ $0 == 0 }) {
                break
            }
            guard let id = String(data: idData, encoding: .isoLatin1),
                  id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
            else {
                throw ManagedAudioMetadataEditError.malformedContainer("ID3")
            }
            let size: Int = if version == 2 {
                Int(data[offset + 3]) << 16
                    | Int(data[offset + 4]) << 8
                    | Int(data[offset + 5])
            } else if version == 4 {
                try synchsafe(data, at: offset + 4)
            } else {
                try data.uint32BE(at: offset + 4).boundedInt
            }
            let end = offset + headerSize + size
            guard size >= 0, end <= data.count else {
                throw ManagedAudioMetadataEditError.malformedContainer("ID3")
            }
            result.append(Frame(id: id, raw: data.subdata(in: offset ..< end)))
            offset = end
        }
        return result
    }

    private static func textFrame(
        id: String,
        value: String,
        version: Int
    ) -> Data {
        let encoded: Data
        let encodingByte: UInt8
        if version == 4 {
            encoded = Data(value.utf8)
            encodingByte = 3
        } else {
            encoded = value.data(using: .utf16) ?? Data(value.utf8)
            encodingByte = 1
        }
        let payload = Data([encodingByte]) + encoded
        var frame = Data(id.utf8)
        if version == 2 {
            frame.append(UInt8((payload.count >> 16) & 0xFF))
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else if version == 4 {
            frame.append(contentsOf: synchsafeBytes(payload.count))
            frame.append(contentsOf: [0, 0])
        } else {
            frame.appendUInt32BE(UInt32(payload.count))
            frame.append(contentsOf: [0, 0])
        }
        frame.append(payload)
        return frame
    }

    private static func targetFrameIDs(version: Int) -> Set<String> {
        version == 2
            ? ["TT2", "TP1", "TAL", "TYE"]
            : ["TIT2", "TPE1", "TALB", "TDRC", "TYER"]
    }

    private static func synchsafe(_ data: Data, at offset: Int) throws -> Int {
        guard offset + 4 <= data.count else {
            throw ManagedAudioMetadataEditError.malformedContainer("ID3")
        }
        let bytes = data[offset ..< offset + 4]
        guard bytes.allSatisfy({ $0 & 0x80 == 0 }) else {
            throw ManagedAudioMetadataEditError.malformedContainer("ID3")
        }
        return bytes.reduce(0) { ($0 << 7) | Int($1) }
    }

    private static func synchsafeBytes(_ value: Int) -> [UInt8] {
        [21, 14, 7, 0].map { UInt8((value >> $0) & 0x7F) }
    }
}

private enum FLACCommentEditor {
    private struct Block {
        let type: UInt8
        let payload: Data
    }

    static func rewrite(
        _ data: Data,
        edit: ManagedAudioMetadataEdit
    ) throws -> Data {
        guard data.count >= 4, data.prefix(4) == Data("fLaC".utf8) else {
            throw ManagedAudioMetadataEditError.malformedContainer("FLAC")
        }
        var blocks: [Block] = []
        var offset = 4
        var foundLast = false
        while !foundLast {
            guard offset + 4 <= data.count else {
                throw ManagedAudioMetadataEditError.malformedContainer("FLAC")
            }
            let header = data[offset]
            foundLast = header & 0x80 != 0
            let length = Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8
                | Int(data[offset + 3])
            let end = offset + 4 + length
            guard end <= data.count else {
                throw ManagedAudioMetadataEditError.malformedContainer("FLAC")
            }
            blocks.append(
                Block(type: header & 0x7F, payload: data.subdata(in: offset + 4 ..< end))
            )
            offset = end
        }

        let commentIndex = blocks.firstIndex { $0.type == 4 }
        let existing = try commentIndex.map { try comments(from: blocks[$0].payload) }
        let replacement = Block(
            type: 4,
            payload: makeComments(existing: existing, edit: edit)
        )
        if let commentIndex {
            blocks[commentIndex] = replacement
        } else {
            blocks.insert(replacement, at: min(1, blocks.count))
        }

        var result = Data("fLaC".utf8)
        for (index, block) in blocks.enumerated() {
            guard block.payload.count <= 0x00FF_FFFF else {
                throw ManagedAudioMetadataEditError.malformedContainer("FLAC")
            }
            result.append(block.type | (index == blocks.count - 1 ? 0x80 : 0))
            result.appendUInt24BE(block.payload.count)
            result.append(block.payload)
        }
        result.append(data.suffix(from: offset))
        return result
    }

    private struct Comments {
        let vendor: Data
        let values: [String]
    }

    private static func comments(from data: Data) throws -> Comments {
        var cursor = 0
        let vendorLength = try data.uint32LE(at: cursor).boundedInt
        cursor += 4
        guard cursor + vendorLength <= data.count else {
            throw ManagedAudioMetadataEditError.malformedContainer("FLAC")
        }
        let vendor = data.subdata(in: cursor ..< cursor + vendorLength)
        cursor += vendorLength
        let count = try data.uint32LE(at: cursor).boundedInt
        cursor += 4
        var values: [String] = []
        for _ in 0 ..< count {
            let length = try data.uint32LE(at: cursor).boundedInt
            cursor += 4
            guard cursor + length <= data.count,
                  let value = String(
                      data: data.subdata(in: cursor ..< cursor + length),
                      encoding: .utf8
                  )
            else {
                throw ManagedAudioMetadataEditError.malformedContainer("FLAC")
            }
            values.append(value)
            cursor += length
        }
        return Comments(vendor: vendor, values: values)
    }

    private static func makeComments(
        existing: Comments?,
        edit: ManagedAudioMetadataEdit
    ) -> Data {
        let targets = Set(["TITLE", "ARTIST", "ALBUM", "DATE", "YEAR"])
        var values = existing?.values.filter { value in
            guard let separator = value.firstIndex(of: "=") else { return true }
            return !targets.contains(value[..<separator].uppercased())
        } ?? []
        values.append("TITLE=\(edit.title)")
        values.append("ARTIST=\(edit.artist)")
        values.append("ALBUM=\(edit.album)")
        if let year = edit.year {
            values.append("DATE=\(year)")
        }
        let vendor = existing?.vendor ?? Data("Cadence".utf8)
        var result = Data()
        result.appendUInt32LE(UInt32(vendor.count))
        result.append(vendor)
        result.appendUInt32LE(UInt32(values.count))
        for value in values {
            let bytes = Data(value.utf8)
            result.appendUInt32LE(UInt32(bytes.count))
            result.append(bytes)
        }
        return result
    }
}
