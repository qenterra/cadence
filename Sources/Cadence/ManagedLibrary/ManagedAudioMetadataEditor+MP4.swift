import Foundation

enum MP4MetadataEditor {
    private enum SizeEncoding {
        case normal
        case extended
        case toEnd
    }

    private struct Atom {
        let type: Data
        let payload: Data
        var sizeEncoding = SizeEncoding.normal

        var encoded: Data {
            var data = Data()
            let normalSize = payload.count + 8
            switch sizeEncoding {
            case .normal where normalSize <= Int(UInt32.max):
                data.appendUInt32BE(UInt32(normalSize))
            case .normal, .extended:
                data.appendUInt32BE(1)
                data.append(type)
                data.appendUInt64BE(UInt64(payload.count + 16))
                data.append(payload)
                return data
            case .toEnd:
                data.appendUInt32BE(0)
            }
            data.append(type)
            data.append(payload)
            return data
        }
    }

    static func rewrite(
        _ data: Data,
        edit: ManagedAudioMetadataEdit
    ) throws -> Data {
        var atoms = try parseAtoms(data)
        guard let moovIndex = atoms.firstIndex(where: { $0.type == fourCC("moov") }) else {
            throw ManagedAudioMetadataEditError.malformedContainer("M4A")
        }
        let movieChildren = try parseAtoms(atoms[moovIndex].payload)
        guard
            !atoms.contains(where: { $0.type == fourCC("moof") }),
            !movieChildren.contains(where: { $0.type == fourCC("mvex") })
        else {
            throw ManagedAudioMetadataEditError.unsupportedContainer("fragmented M4A")
        }
        let originalMoovSize = atoms[moovIndex].encoded.count
        let originalMoovEnd = atoms[..<moovIndex].reduce(0) {
            $0 + $1.encoded.count
        } + originalMoovSize
        var rewrittenMoov = try rewritingMoov(atoms[moovIndex], edit: edit)
        let offsetDelta = rewrittenMoov.encoded.count - originalMoovSize
        if offsetDelta != 0,
           atoms[(moovIndex + 1)...].contains(where: { $0.type == fourCC("mdat") }) {
            rewrittenMoov = try adjustingChunkOffsets(
                in: rewrittenMoov,
                after: UInt64(originalMoovEnd),
                by: offsetDelta
            )
        }
        atoms[moovIndex] = rewrittenMoov
        return atoms.reduce(into: Data()) { $0.append($1.encoded) }
    }

    private static func rewritingMoov(
        _ moov: Atom,
        edit: ManagedAudioMetadataEdit
    ) throws -> Atom {
        var children = try parseAtoms(moov.payload)
        let udtaIndex: Int
        if let existing = children.firstIndex(where: { $0.type == fourCC("udta") }) {
            udtaIndex = existing
        } else {
            children.append(Atom(type: fourCC("udta"), payload: Data()))
            udtaIndex = children.count - 1
        }
        children[udtaIndex] = try rewritingUdta(children[udtaIndex], edit: edit)
        return Atom(
            type: moov.type,
            payload: children.reduce(into: Data()) { $0.append($1.encoded) },
            sizeEncoding: moov.sizeEncoding
        )
    }

    private static func rewritingUdta(
        _ udta: Atom,
        edit: ManagedAudioMetadataEdit
    ) throws -> Atom {
        var children = try parseAtoms(udta.payload)
        let metaIndex: Int
        if let existing = children.firstIndex(where: { $0.type == fourCC("meta") }) {
            metaIndex = existing
        } else {
            children.append(
                Atom(type: fourCC("meta"), payload: Data(repeating: 0, count: 4))
            )
            metaIndex = children.count - 1
        }
        children[metaIndex] = try rewritingMeta(children[metaIndex], edit: edit)
        return Atom(
            type: udta.type,
            payload: children.reduce(into: Data()) { $0.append($1.encoded) },
            sizeEncoding: udta.sizeEncoding
        )
    }

    private static func rewritingMeta(
        _ meta: Atom,
        edit: ManagedAudioMetadataEdit
    ) throws -> Atom {
        guard meta.payload.count >= 4 else {
            throw ManagedAudioMetadataEditError.malformedContainer("M4A")
        }
        let prefix = meta.payload.prefix(4)
        var children = try parseAtoms(meta.payload.dropFirst(4))
        let ilstIndex: Int
        if let existing = children.firstIndex(where: { $0.type == fourCC("ilst") }) {
            ilstIndex = existing
        } else {
            children.append(Atom(type: fourCC("ilst"), payload: Data()))
            ilstIndex = children.count - 1
        }
        children[ilstIndex] = try rewritingList(children[ilstIndex], edit: edit)
        return Atom(
            type: meta.type,
            payload: Data(prefix) + children.reduce(into: Data()) { $0.append($1.encoded) },
            sizeEncoding: meta.sizeEncoding
        )
    }

    private static func rewritingList(
        _ list: Atom,
        edit: ManagedAudioMetadataEdit
    ) throws -> Atom {
        var children = try parseAtoms(list.payload)
        let targetTypes = Set([
            fourCC([0xA9, 0x6E, 0x61, 0x6D]),
            fourCC([0xA9, 0x41, 0x52, 0x54]),
            fourCC([0xA9, 0x61, 0x6C, 0x62]),
            fourCC([0xA9, 0x64, 0x61, 0x79]),
        ])
        children.removeAll { targetTypes.contains($0.type) }
        children.append(metadataAtom(type: [0xA9, 0x6E, 0x61, 0x6D], value: edit.title))
        children.append(metadataAtom(type: [0xA9, 0x41, 0x52, 0x54], value: edit.artist))
        children.append(metadataAtom(type: [0xA9, 0x61, 0x6C, 0x62], value: edit.album))
        if let year = edit.year {
            children.append(metadataAtom(type: [0xA9, 0x64, 0x61, 0x79], value: String(year)))
        }
        return Atom(
            type: list.type,
            payload: children.reduce(into: Data()) { $0.append($1.encoded) },
            sizeEncoding: list.sizeEncoding
        )
    }

    private static func metadataAtom(type: [UInt8], value: String) -> Atom {
        var dataPayload = Data(repeating: 0, count: 8)
        dataPayload[3] = 1
        dataPayload.append(Data(value.utf8))
        return Atom(
            type: Data(type),
            payload: Atom(type: fourCC("data"), payload: dataPayload).encoded
        )
    }

    private static func parseAtoms(_ source: some DataProtocol) throws -> [Atom] {
        let data = Data(source)
        var atoms: [Atom] = []
        var offset = 0
        while offset < data.count {
            guard offset + 8 <= data.count else {
                throw ManagedAudioMetadataEditError.malformedContainer("M4A")
            }
            let declaredSize = try data.uint32BE(at: offset)
            let headerSize: Int
            let size: Int
            let sizeEncoding: SizeEncoding
            switch declaredSize {
            case 0:
                headerSize = 8
                size = data.count - offset
                sizeEncoding = .toEnd
            case 1:
                guard offset + 16 <= data.count else {
                    throw ManagedAudioMetadataEditError.malformedContainer("M4A")
                }
                headerSize = 16
                size = try data.uint64BE(at: offset + 8).boundedInt
                sizeEncoding = .extended
            default:
                headerSize = 8
                size = declaredSize.boundedInt
                sizeEncoding = .normal
            }
            guard size >= headerSize, offset + size <= data.count else {
                throw ManagedAudioMetadataEditError.malformedContainer("M4A")
            }
            atoms.append(
                Atom(
                    type: data.subdata(in: offset + 4 ..< offset + 8),
                    payload: data.subdata(in: offset + headerSize ..< offset + size),
                    sizeEncoding: sizeEncoding
                )
            )
            offset += size
        }
        return atoms
    }

    private static func adjustingChunkOffsets(
        in atom: Atom,
        after threshold: UInt64,
        by delta: Int
    ) throws -> Atom {
        if atom.type == fourCC("stco") {
            return try adjusting32BitOffsets(
                in: atom,
                after: threshold,
                by: delta
            )
        }
        if atom.type == fourCC("co64") {
            return try adjusting64BitOffsets(
                in: atom,
                after: threshold,
                by: delta
            )
        }
        let containerTypes = Set([
            fourCC("moov"), fourCC("trak"), fourCC("mdia"),
            fourCC("minf"), fourCC("stbl"),
        ])
        guard containerTypes.contains(atom.type) else {
            return atom
        }
        let children = try parseAtoms(atom.payload).map {
            try adjustingChunkOffsets(in: $0, after: threshold, by: delta)
        }
        return Atom(
            type: atom.type,
            payload: children.reduce(into: Data()) { $0.append($1.encoded) },
            sizeEncoding: atom.sizeEncoding
        )
    }

    private static func adjusting32BitOffsets(
        in atom: Atom,
        after threshold: UInt64,
        by delta: Int
    ) throws -> Atom {
        guard atom.payload.count >= 8 else {
            throw ManagedAudioMetadataEditError.malformedContainer("M4A")
        }
        var payload = atom.payload
        let count = try payload.uint32BE(at: 4).boundedInt
        guard 8 + count * 4 == payload.count else {
            throw ManagedAudioMetadataEditError.malformedContainer("M4A")
        }
        for index in 0 ..< count {
            let offset = try UInt64(payload.uint32BE(at: 8 + index * 4))
            guard offset >= threshold else { continue }
            let adjusted = try adjustedOffset(offset, by: delta)
            guard adjusted <= UInt64(UInt32.max) else {
                throw ManagedAudioMetadataEditError.unsupportedContainer("M4A")
            }
            payload.replaceSubrange(
                8 + index * 4 ..< 12 + index * 4,
                with: uint32BEBytes(UInt32(adjusted))
            )
        }
        return Atom(type: atom.type, payload: payload, sizeEncoding: atom.sizeEncoding)
    }

    private static func adjusting64BitOffsets(
        in atom: Atom,
        after threshold: UInt64,
        by delta: Int
    ) throws -> Atom {
        guard atom.payload.count >= 8 else {
            throw ManagedAudioMetadataEditError.malformedContainer("M4A")
        }
        var payload = atom.payload
        let count = try payload.uint32BE(at: 4).boundedInt
        guard 8 + count * 8 == payload.count else {
            throw ManagedAudioMetadataEditError.malformedContainer("M4A")
        }
        for index in 0 ..< count {
            let range = 8 + index * 8 ..< 16 + index * 8
            let offset = try payload.uint64BE(at: range.lowerBound)
            guard offset >= threshold else { continue }
            try payload.replaceSubrange(
                range,
                with: uint64BEBytes(adjustedOffset(offset, by: delta))
            )
        }
        return Atom(type: atom.type, payload: payload, sizeEncoding: atom.sizeEncoding)
    }

    private static func adjustedOffset(_ value: UInt64, by delta: Int) throws -> UInt64 {
        if delta >= 0 {
            let (result, overflow) = value.addingReportingOverflow(UInt64(delta))
            guard !overflow else {
                throw ManagedAudioMetadataEditError.unsupportedContainer("M4A")
            }
            return result
        }
        let amount = UInt64(-delta)
        guard value >= amount else {
            throw ManagedAudioMetadataEditError.malformedContainer("M4A")
        }
        return value - amount
    }
}
