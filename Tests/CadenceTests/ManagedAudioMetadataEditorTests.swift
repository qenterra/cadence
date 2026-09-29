import AVFoundation
@testable import Cadence
import Foundation
import QenTerraFoundation
import Testing

struct ManagedAudioMetadataEditorTests {
    @Test("WAV metadata edits preserve audio and publish the edited source of truth")
    func wavRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Metadata-\(UUID().uuidString).wav"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSilentWAV(to: url)

        let edit = ManagedAudioMetadataEdit(
            title: "Blue Hour",
            artist: "Northbound",
            album: "Afterlight",
            year: 2026
        )
        let metadata = try await ManagedTrackMetadataTransaction().perform(
            trackID: UUID(),
            fileURL: url,
            edit: edit
        ) { repair in
            #expect(repair.metadata.title == "Blue Hour")
            #expect(repair.metadata.artist == "Northbound")
            #expect(repair.metadata.album == "Afterlight")
            #expect(repair.metadata.year == 2026)
            let actualContentHash = try await ContentHasher().sha256(of: url)
            #expect(repair.contentHash == actualContentHash)
        }

        #expect(metadata.title == "Blue Hour")
        #expect(metadata.artist == "Northbound")
        #expect(metadata.album == "Afterlight")
        #expect(metadata.year == 2026)
        #expect(metadata.duration > 0.09)
        let encoded = try Data(contentsOf: url)
        #expect(
            try AudioMetadataContainerEditor.rewrite(
                encoded,
                fileExtension: "wav",
                edit: edit
            ) == encoded
        )
    }

    @Test("Binary editors preserve unrelated metadata blocks")
    func formatSpecificEditorsPreserveUnrelatedData() throws {
        let marker = Data("cadence-preserve-marker".utf8)
        let edit = ManagedAudioMetadataEdit(
            title: "Title",
            artist: "Artist",
            album: "Album",
            year: 2026
        )

        for fixture in AudioMetadataEditingFixtures.all(marker: marker) {
            let rewritten = try AudioMetadataContainerEditor.rewrite(
                fixture.data,
                fileExtension: fixture.fileExtension,
                edit: edit
            )
            #expect(rewritten.contains(marker))
            #expect(rewritten != fixture.data)
        }
    }

    @Test("M4A edits keep chunk offsets pointed at media data")
    func m4aChunkOffsetsFollowGrowingMetadata() throws {
        let marker = Data("audio-payload".utf8)
        let original = AudioMetadataEditingFixtures.offsetM4A(marker: marker)
        let rewritten = try AudioMetadataContainerEditor.rewrite(
            original,
            fileExtension: "m4a",
            edit: ManagedAudioMetadataEdit(
                title: "A Much Longer Track Title",
                artist: "Artist",
                album: "Album",
                year: 2026
            )
        )

        let stcoType = try #require(rewritten.range(of: Data("stco".utf8)))
        let offset = Int(readUInt32BE(rewritten, at: stcoType.lowerBound + 12))
        #expect(rewritten.subdata(in: offset ..< offset + marker.count) == marker)
    }

    @Test("Fragmented M4A is rejected before any bytes are changed")
    func fragmentedM4AIsRejected() {
        #expect(throws: ManagedAudioMetadataEditError.self) {
            _ = try AudioMetadataContainerEditor.rewrite(
                AudioMetadataEditingFixtures.fragmentedM4A(),
                fileExtension: "m4a",
                edit: ManagedAudioMetadataEdit(
                    title: "Title",
                    artist: "Artist",
                    album: "Album",
                    year: 2026
                )
            )
        }
    }

    @Test("ID3v2.3 writes the standard TYER year frame")
    func id3VersionThreeUsesTYER() throws {
        let rewritten = try AudioMetadataContainerEditor.rewrite(
            AudioMetadataEditingFixtures.id3VersionThree(),
            fileExtension: "mp3",
            edit: ManagedAudioMetadataEdit(
                title: "Title",
                artist: "Artist",
                album: "Album",
                year: 2026
            )
        )

        #expect(rewritten.contains(Data("TYER".utf8)))
        #expect(!rewritten.contains(Data("TDRC".utf8)))
    }

    @Test("Database failure restores the original managed audio file")
    func persistenceFailureRollsBackFile() async throws {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Metadata-Rollback-\(UUID().uuidString).wav"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSilentWAV(to: url)
        let original = try Data(contentsOf: url)

        await #expect(throws: MetadataPersistenceFailure.self) {
            _ = try await ManagedTrackMetadataTransaction().perform(
                trackID: UUID(),
                fileURL: url,
                edit: ManagedAudioMetadataEdit(
                    title: "Changed",
                    artist: "Changed",
                    album: "Changed",
                    year: 2026
                )
            ) { _ in
                throw MetadataPersistenceFailure()
            }
        }

        #expect(try Data(contentsOf: url) == original)
    }

    @Test("Startup recovery restores an edit interrupted before catalog commit")
    func preparedJournalRestoresOriginalFile() async throws {
        let musicDirectory = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Metadata-Recovery-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: musicDirectory) }
        let package = ManagedLibraryPackage(
            location: ManagedLibraryLocation(musicDirectory: musicDirectory)
        )
        try FileManager.default.createDirectory(
            at: package.mediaDirectoryURL,
            withIntermediateDirectories: true
        )
        let trackID = UUID()
        let relativePath = "Media/\(trackID.uuidString).wav"
        let fileURL = try package.location.resolve(
            relativePath: relativePath,
            directoryHint: .notDirectory
        )
        try writeSilentWAV(to: fileURL)
        let original = try Data(contentsOf: fileURL)
        let store = ManagedTrackMetadataEditManifestStore(package: package)
        try await prepareInterruptedEdit(
            trackID: trackID,
            relativePath: relativePath,
            fileURL: fileURL,
            store: store
        )
        try await ManagedAudioMetadataEditor().write(
            ManagedAudioMetadataEdit(
                title: "Interrupted",
                artist: "Artist",
                album: "Album",
                year: 2026
            ),
            to: fileURL
        )

        let repository = try LibraryRepository(
            modelContainer: LibraryContainerFactory.inMemory()
        )
        let recovered = try await ManagedTrackMetadataTransaction(
            package: package
        ).recover(repository: repository)

        #expect(recovered == 0)
        #expect(try Data(contentsOf: fileURL) == original)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path)
                .isEmpty
        )
    }

    private func writeSilentWAV(to url: URL) throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        )
        let frames: AVAudioFrameCount = 4410
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        )
        buffer.frameLength = frames
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func prepareInterruptedEdit(
        trackID: UUID,
        relativePath: String,
        fileURL: URL,
        store: ManagedTrackMetadataEditManifestStore
    ) async throws {
        let manifest = try await ManagedTrackMetadataEditManifest(
            operationID: UUID(),
            trackID: trackID,
            relativeMediaPath: relativePath,
            originalHash: ContentHasher().sha256(of: fileURL),
            state: .prepared
        )
        try store.save(manifest)
        try FileManager.default.copyItem(
            at: fileURL,
            to: store.backupURL(manifest)
        )
    }

    private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        data[offset ..< offset + 4].reduce(0) {
            ($0 << 8) | UInt32($1)
        }
    }
}

private struct MetadataPersistenceFailure: Error {}

private enum AudioMetadataEditingFixtures {
    struct Fixture {
        let fileExtension: String
        let data: Data
    }

    static func all(marker: Data) -> [Fixture] {
        [
            Fixture(fileExtension: "mp3", data: id3(marker: marker)),
            Fixture(fileExtension: "aac", data: id3(marker: marker)),
            Fixture(fileExtension: "flac", data: flac(marker: marker)),
            Fixture(fileExtension: "wav", data: riff(marker: marker)),
            Fixture(fileExtension: "aiff", data: aiff(marker: marker)),
            Fixture(fileExtension: "m4a", data: m4a(marker: marker)),
        ]
    }

    static func offsetM4A(marker: Data) -> Data {
        let ftyp = atom(type: "ftyp", payload: Data("M4A \0\0\0\0M4A ".utf8))
        func movie(offset: UInt32) -> Data {
            var stcoPayload = Data(repeating: 0, count: 4)
            appendUInt32BE(1, to: &stcoPayload)
            appendUInt32BE(offset, to: &stcoPayload)
            return atom(
                type: "moov",
                payload: atom(
                    type: "trak",
                    payload: atom(
                        type: "mdia",
                        payload: atom(
                            type: "minf",
                            payload: atom(
                                type: "stbl",
                                payload: atom(type: "stco", payload: stcoPayload)
                            )
                        )
                    )
                ) + atom(
                    type: "udta",
                    payload: atom(
                        type: "meta",
                        payload: Data(repeating: 0, count: 4)
                            + atom(type: "ilst", payload: Data())
                    )
                )
            )
        }
        let placeholder = movie(offset: 0)
        let mediaOffset = UInt32(ftyp.count + placeholder.count + 8)
        return ftyp + movie(offset: mediaOffset) + atom(type: "mdat", payload: marker)
    }

    static func fragmentedM4A() -> Data {
        atom(type: "ftyp", payload: Data("M4A \0\0\0\0M4A ".utf8))
            + atom(type: "moov", payload: atom(type: "mvex", payload: Data()))
            + atom(type: "moof", payload: Data())
            + atom(type: "mdat", payload: Data("audio".utf8))
    }

    static func id3VersionThree() -> Data {
        id3(marker: Data("preserved".utf8))
    }

    private static func id3(marker: Data) -> Data {
        var frame = Data("TXXX".utf8)
        frame.append(contentsOf: [0, 0, 0, UInt8(marker.count), 0, 0])
        frame.append(marker)
        var data = Data("ID3".utf8)
        data.append(contentsOf: [3, 0, 0, 0, 0, 0, UInt8(frame.count)])
        data.append(frame)
        data.append(Data([0xFF, 0xFB, 0x90, 0x64]))
        return data
    }

    private static func flac(marker: Data) -> Data {
        var data = Data("fLaC".utf8)
        data.append(0x80 | 2)
        appendUInt24(marker.count, to: &data)
        data.append(marker)
        return data
    }

    private static func riff(marker: Data) -> Data {
        var body = Data("WAVE".utf8)
        body.append(Data("JUNK".utf8))
        appendUInt32LE(UInt32(marker.count), to: &body)
        body.append(marker)
        if marker.count.isMultiple(of: 2) == false {
            body.append(0)
        }
        var data = Data("RIFF".utf8)
        appendUInt32LE(UInt32(body.count), to: &data)
        data.append(body)
        return data
    }

    private static func aiff(marker: Data) -> Data {
        var body = Data("AIFF".utf8)
        body.append(Data("ANNO".utf8))
        appendUInt32BE(UInt32(marker.count), to: &body)
        body.append(marker)
        if marker.count.isMultiple(of: 2) == false {
            body.append(0)
        }
        var data = Data("FORM".utf8)
        appendUInt32BE(UInt32(body.count), to: &data)
        data.append(body)
        return data
    }

    private static func m4a(marker: Data) -> Data {
        atom(type: "ftyp", payload: Data("M4A \0\0\0\0M4A ".utf8))
            + atom(type: "free", payload: marker)
            + atom(
                type: "moov",
                payload: atom(
                    type: "udta",
                    payload: atom(
                        type: "meta",
                        payload: Data(repeating: 0, count: 4)
                            + atom(type: "ilst", payload: Data())
                    )
                )
            )
    }

    private static func atom(type: String, payload: Data) -> Data {
        var data = Data()
        appendUInt32BE(UInt32(payload.count + 8), to: &data)
        data.append(Data(type.utf8))
        data.append(payload)
        return data
    }

    private static func appendUInt24(_ value: Int, to data: inout Data) {
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}
