@testable import Cadence
import Foundation
import Testing

struct ImportInspectionServiceTests {
    @Test("Inspection never exceeds four active audio files")
    func boundedConcurrency() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Inspection-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        for index in 0 ..< 12 {
            let url = root.appending(path: "\(index).wav")
            try Data([UInt8(index)]).write(to: url)
        }

        let inspector = ConcurrencyRecordingInspector()
        let service = ImportInspectionService(
            inspector: inspector,
            maximumConcurrentFiles: 99
        )

        let candidates = try await service.inspect(
            source: ImportSource(urls: [root])
        )

        #expect(candidates.count == 12)
        #expect(await inspector.maximumActiveCount == 4)
        #expect(candidates.map(\.sourceFile.relativePath) == (0 ..< 12).map {
            "\($0).wav"
        }.sorted())
    }

    @Test("Progress starts at zero and reaches the exact candidate total")
    func realProgress() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Cadence-Progress-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        for index in 0 ..< 3 {
            try Data([0]).write(
                to: root.appending(path: "\(index).wav")
            )
        }

        let recorder = ProgressRecorder()
        let service = ImportInspectionService(
            inspector: ConcurrencyRecordingInspector()
        )
        _ = try await service.inspect(
            source: ImportSource(urls: [root])
        ) { progress in
            await recorder.append(progress)
        }
        let values = await recorder.values

        #expect(values.first?.completedCount == 0)
        #expect(values.first?.totalCount == 3)
        #expect(values.last?.completedCount == 3)
        #expect(values.last?.fractionCompleted == 1)
    }
}

private actor ConcurrencyRecordingInspector: ImportFileInspecting {
    private(set) var maximumActiveCount = 0
    private var activeCount = 0

    func inspect(
        audio: ScannedSourceFile,
        among _: [ScannedSourceFile]
    ) async throws -> ImportInspectionDraft {
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer {
            activeCount -= 1
        }

        try await Task.sleep(for: .milliseconds(15))
        return ImportInspectionDraft(
            sourceFile: audio,
            sizeInBytes: 1,
            metadata: ScannedAudioMetadata(
                title: audio.url.deletingPathExtension().lastPathComponent,
                artist: "Test Artist",
                album: "Test Album",
                year: nil,
                trackNumber: nil,
                discNumber: nil,
                duration: 1,
                codec: "lpcm",
                container: "WAV",
                sampleRate: 44100,
                channelCount: 2,
                bitrate: nil,
                bitDepth: 16,
                spatialFormat: .stereo
            ),
            contentHash: audio.url.lastPathComponent,
            lyrics: .unavailable,
            failure: nil
        )
    }
}

private actor ProgressRecorder {
    private(set) var values: [ImportInspectionProgress] = []

    func append(_ progress: ImportInspectionProgress) {
        values.append(progress)
    }
}
