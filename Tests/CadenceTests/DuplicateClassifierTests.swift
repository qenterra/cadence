@testable import Cadence
import Foundation
import Testing

struct DuplicateClassifierTests {
    @Test("Committed exact and metadata matches use distinct dispositions")
    func committedEvidence() {
        let exact = draft(
            filename: "Exact.wav",
            title: "Exact",
            hash: "exact"
        )
        let possible = draft(
            filename: "Possible.wav",
            title: "Possible",
            hash: "new-master"
        )
        let evidence = ImportDuplicateEvidence(
            exactHashes: ["exact"],
            metadataIdentities: [
                ImportMetadataIdentity(
                    artist: "Test Artist",
                    title: "Possible"
                ),
            ]
        )

        let candidates = DuplicateClassifier().classify(
            [exact, possible],
            evidence: evidence
        )

        #expect(
            candidates.map(\.duplicateDisposition)
                == [.exactDuplicate, .possibleDuplicate]
        )
    }

    @Test("Batch classification keeps the first file and flags later matches")
    func withinBatchEvidence() {
        let first = draft(
            filename: "First.wav",
            title: "Same Song",
            hash: "hash-a"
        )
        let exact = draft(
            filename: "Second.wav",
            title: "Other Metadata",
            hash: "hash-a"
        )
        let possible = draft(
            filename: "Third.wav",
            title: "Same Song",
            hash: "hash-b"
        )

        let candidates = DuplicateClassifier().classify(
            [first, exact, possible],
            evidence: .empty
        )

        #expect(
            candidates.map(\.duplicateDisposition)
                == [.unique, .exactDuplicate, .possibleDuplicate]
        )
    }

    private func draft(
        filename: String,
        title: String,
        hash: String
    ) -> ImportInspectionDraft {
        let url = URL(filePath: "/tmp/\(filename)")
        return ImportInspectionDraft(
            sourceFile: ScannedSourceFile(
                url: url,
                relativePath: filename,
                kind: .audio(.wav)
            ),
            sizeInBytes: 12,
            metadata: ScannedAudioMetadata(
                title: title,
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
            contentHash: hash,
            lyrics: .unavailable,
            failure: nil
        )
    }
}
