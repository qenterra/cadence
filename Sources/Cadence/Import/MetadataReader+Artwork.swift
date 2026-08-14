import AVFoundation
import Foundation
import ImageIO

private enum FLACArtworkReadError: LocalizedError {
    case invalidSignature
    case truncatedBlockHeader
    case truncatedBlock
    case malformedPictureBlock

    var errorDescription: String? {
        switch self {
        case .invalidSignature:
            "The file does not contain a valid FLAC signature."
        case .truncatedBlockHeader:
            "The FLAC metadata block header is truncated."
        case .truncatedBlock:
            "A FLAC metadata block is truncated."
        case .malformedPictureBlock:
            "The FLAC picture block is malformed."
        }
    }
}

extension MetadataReader {
    func embeddedArtwork(
        metadataItems: [AVMetadataItem],
        url: URL
    ) async throws -> EmbeddedArtworkPayload? {
        let data: Data? = if url.pathExtension.lowercased() == "flac" {
            try flacPictureData(url: url)
        } else {
            try await MetadataValueResolver(items: metadataItems).data(
                commonIdentifier: .commonIdentifierArtwork,
                rawKeys: ["APIC", "COVR", "PICTURE"]
            )
        }
        guard let data, !data.isEmpty else {
            return nil
        }
        return artworkPayload(data: data)
    }

    func artworkPayload(
        data: Data
    ) -> EmbeddedArtworkPayload? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
            ),
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0,
            height > 0
        else {
            return nil
        }
        let format = artworkFormat(
            typeIdentifier: CGImageSourceGetType(source)
        )
        return EmbeddedArtworkPayload(
            metadata: EmbeddedArtworkMetadata(
                contentHash: ContentHasher().sha256(of: data),
                format: format,
                pixelWidth: width,
                pixelHeight: height
            ),
            data: data
        )
    }

    func artworkFormat(
        typeIdentifier: CFString?
    ) -> String {
        let identifier = typeIdentifier as String? ?? ""
        if identifier.localizedCaseInsensitiveContains("png") {
            return "png"
        }
        if identifier.localizedCaseInsensitiveContains("heic")
            || identifier.localizedCaseInsensitiveContains("heif") {
            return "heic"
        }
        return "jpg"
    }

    func flacPictureData(
        url: URL
    ) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("fLaC".utf8) else {
            throw FLACArtworkReadError.invalidSignature
        }

        var isLastBlock = false
        while !isLastBlock {
            guard
                let header = try handle.read(upToCount: 4),
                header.count == 4
            else {
                throw FLACArtworkReadError.truncatedBlockHeader
            }
            isLastBlock = header[0] & 0x80 != 0
            let type = header[0] & 0x7F
            let length = Int(header[1]) << 16
                | Int(header[2]) << 8
                | Int(header[3])
            guard
                let block = try handle.read(upToCount: length),
                block.count == length
            else {
                throw FLACArtworkReadError.truncatedBlock
            }
            if type == 6 {
                guard let payload = flacPicturePayload(block) else {
                    throw FLACArtworkReadError.malformedPictureBlock
                }
                return payload
            }
        }
        return nil
    }

    func flacPicturePayload(
        _ block: Data
    ) -> Data? {
        var cursor = 0
        guard readUInt32(block, cursor: &cursor) != nil else {
            return nil
        }
        guard
            let mimeLength = readUInt32(block, cursor: &cursor),
            advance(&cursor, by: Int(mimeLength), within: block),
            let descriptionLength = readUInt32(block, cursor: &cursor),
            advance(&cursor, by: Int(descriptionLength), within: block)
        else {
            return nil
        }
        for _ in 0 ..< 4 {
            guard readUInt32(block, cursor: &cursor) != nil else {
                return nil
            }
        }
        guard
            let payloadLength = readUInt32(block, cursor: &cursor),
            payloadLength > 0,
            cursor + Int(payloadLength) <= block.count
        else {
            return nil
        }
        return block.subdata(
            in: cursor ..< cursor + Int(payloadLength)
        )
    }

    func readUInt32(
        _ data: Data,
        cursor: inout Int
    ) -> UInt32? {
        guard cursor + 4 <= data.count else {
            return nil
        }
        let value = data[cursor ..< cursor + 4].reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        cursor += 4
        return value
    }

    func advance(
        _ cursor: inout Int,
        by count: Int,
        within data: Data
    ) -> Bool {
        guard count >= 0, cursor + count <= data.count else {
            return false
        }
        cursor += count
        return true
    }
}
