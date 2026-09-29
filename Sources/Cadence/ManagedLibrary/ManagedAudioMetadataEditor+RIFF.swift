import Foundation

enum RIFFInfoEditor {
    static func rewrite(
        _ data: Data,
        edit: ManagedAudioMetadataEdit
    ) throws -> Data {
        guard data.count >= 12,
              data.prefix(4) == Data("RIFF".utf8),
              data.subdata(in: 8 ..< 12) == Data("WAVE".utf8)
        else {
            throw ManagedAudioMetadataEditError.malformedContainer("WAV")
        }
        let chunks = try parseChunks(data, start: 12, end: data.count, endian: .little)
        var preserved: [BinaryChunk] = []
        var infoValues: [BinaryChunk] = []
        var existingID3 = Data()
        for chunk in chunks {
            if chunk.id == Data("LIST".utf8),
               chunk.payload.count >= 4,
               chunk.payload.prefix(4) == Data("INFO".utf8) {
                infoValues += try parseChunks(
                    chunk.payload,
                    start: 4,
                    end: chunk.payload.count,
                    endian: .little
                )
            } else if [Data("ID3 ".utf8), Data("id3 ".utf8)].contains(chunk.id) {
                existingID3 = chunk.payload
            } else {
                preserved.append(chunk)
            }
        }
        let targets = Set(["INAM", "IART", "IPRD", "ICRD"])
        infoValues.removeAll { chunk in
            String(data: chunk.id, encoding: .ascii).map(targets.contains) ?? false
        }
        infoValues += [
            BinaryChunk(id: Data("INAM".utf8), payload: cString(edit.title)),
            BinaryChunk(id: Data("IART".utf8), payload: cString(edit.artist)),
            BinaryChunk(id: Data("IPRD".utf8), payload: cString(edit.album)),
        ]
        if let year = edit.year {
            infoValues.append(BinaryChunk(id: Data("ICRD".utf8), payload: cString(String(year))))
        }
        let infoPayload = Data("INFO".utf8)
            + serializeChunks(infoValues, endian: .little)
        preserved.append(BinaryChunk(id: Data("LIST".utf8), payload: infoPayload))
        try preserved.append(
            BinaryChunk(
                id: Data("ID3 ".utf8),
                payload: ID3Editor.rewrite(existingID3, edit: edit)
            )
        )
        let body = Data("WAVE".utf8) + serializeChunks(preserved, endian: .little)
        var result = Data("RIFF".utf8)
        result.appendUInt32LE(UInt32(body.count))
        result.append(body)
        return result
    }
}

enum AIFFMetadataEditor {
    static func rewrite(
        _ data: Data,
        edit: ManagedAudioMetadataEdit
    ) throws -> Data {
        guard data.count >= 12,
              data.prefix(4) == Data("FORM".utf8),
              [Data("AIFF".utf8), Data("AIFC".utf8)]
              .contains(data.subdata(in: 8 ..< 12))
        else {
            throw ManagedAudioMetadataEditError.malformedContainer("AIFF")
        }
        let formType = data.subdata(in: 8 ..< 12)
        var chunks = try parseChunks(data, start: 12, end: data.count, endian: .big)
        let existingID3 = chunks.first { $0.id == Data("ID3 ".utf8) }?.payload
            ?? Data()
        let rewrittenID3 = try ID3Editor.rewrite(existingID3, edit: edit)
        chunks.removeAll {
            [Data("NAME".utf8), Data("AUTH".utf8), Data("ID3 ".utf8)]
                .contains($0.id)
        }
        chunks.append(BinaryChunk(id: Data("NAME".utf8), payload: Data(edit.title.utf8)))
        chunks.append(BinaryChunk(id: Data("AUTH".utf8), payload: Data(edit.artist.utf8)))
        chunks.append(BinaryChunk(id: Data("ID3 ".utf8), payload: rewrittenID3))
        let body = formType + serializeChunks(chunks, endian: .big)
        var result = Data("FORM".utf8)
        result.appendUInt32BE(UInt32(body.count))
        result.append(body)
        return result
    }
}

enum ChunkEndian {
    case big
    case little
}

struct BinaryChunk {
    let id: Data
    let payload: Data
}

func parseChunks(
    _ data: Data,
    start: Int,
    end: Int,
    endian: ChunkEndian
) throws -> [BinaryChunk] {
    var result: [BinaryChunk] = []
    var offset = start
    while offset < end {
        guard offset + 8 <= end else {
            throw ManagedAudioMetadataEditError.malformedContainer("RIFF")
        }
        let size = try (endian == .little
            ? data.uint32LE(at: offset + 4)
            : data.uint32BE(at: offset + 4)).boundedInt
        let payloadStart = offset + 8
        let payloadEnd = payloadStart + size
        guard payloadEnd <= end else {
            throw ManagedAudioMetadataEditError.malformedContainer("RIFF")
        }
        result.append(
            BinaryChunk(
                id: data.subdata(in: offset ..< offset + 4),
                payload: data.subdata(in: payloadStart ..< payloadEnd)
            )
        )
        offset = payloadEnd + (size.isMultiple(of: 2) ? 0 : 1)
    }
    return result
}

func serializeChunks(
    _ chunks: [BinaryChunk],
    endian: ChunkEndian
) -> Data {
    chunks.reduce(into: Data()) { result, chunk in
        result.append(chunk.id)
        switch endian {
        case .big: result.appendUInt32BE(UInt32(chunk.payload.count))
        case .little: result.appendUInt32LE(UInt32(chunk.payload.count))
        }
        result.append(chunk.payload)
        if !chunk.payload.count.isMultiple(of: 2) {
            result.append(0)
        }
    }
}

func cString(_ value: String) -> Data {
    Data(value.utf8) + Data([0])
}

func fourCC(_ value: String) -> Data {
    Data(value.utf8)
}

func fourCC(_ bytes: [UInt8]) -> Data {
    Data(bytes)
}

extension UInt32 {
    var boundedInt: Int {
        Int(self)
    }
}

extension UInt64 {
    var boundedInt: Int {
        get throws {
            guard self <= UInt64(Int.max) else {
                throw ManagedAudioMetadataEditError.malformedContainer("binary")
            }
            return Int(self)
        }
    }
}

func uint32BEBytes(_ value: UInt32) -> Data {
    var data = Data()
    data.appendUInt32BE(value)
    return data
}

func uint64BEBytes(_ value: UInt64) -> Data {
    var data = Data()
    data.appendUInt64BE(value)
    return data
}

extension Data {
    func uint32BE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw ManagedAudioMetadataEditError.malformedContainer("binary")
        }
        return self[offset ..< offset + 4].reduce(0) {
            ($0 << 8) | UInt32($1)
        }
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw ManagedAudioMetadataEditError.malformedContainer("binary")
        }
        return self[offset ..< offset + 4].enumerated().reduce(0) {
            $0 | UInt32($1.element) << UInt32($1.offset * 8)
        }
    }

    func uint64BE(at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= count else {
            throw ManagedAudioMetadataEditError.malformedContainer("binary")
        }
        return self[offset ..< offset + 8].reduce(0) {
            ($0 << 8) | UInt64($1)
        }
    }

    mutating func appendUInt24BE(_ value: Int) {
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func appendUInt64BE(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xFF))
        append(UInt8((value >> 48) & 0xFF))
        append(UInt8((value >> 40) & 0xFF))
        append(UInt8((value >> 32) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
