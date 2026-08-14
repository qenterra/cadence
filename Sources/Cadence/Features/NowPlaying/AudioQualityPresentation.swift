import Foundation

struct AudioQualityDetail: Equatable, Sendable {
    let label: String
    let value: String
}

/// Separates the glanceable quality badge from playback diagnostics.
/// Now Playing uses `badge`; the detail popover is the only consumer of
/// renderer, route, spatial-format, and transition information.
struct AudioQualityPresentation: Equatable, Sendable {
    let badge: String
    let details: [AudioQualityDetail]

    init(path: AudioPathSnapshot) {
        let codec = path.codec.uppercased()
        let sampleRate = Self.sampleRate(path.sourceSampleRate)
        let bitDepth = path.sourceBitDepth.map { "\($0)-bit" }
        badge = ([codec] + [bitDepth, sampleRate].compactMap(\.self))
            .joined(separator: " · ")

        details = [
            AudioQualityDetail(
                label: String(localized: "Format"),
                value: Self.format(path, codec: codec, sampleRate: sampleRate)
            ),
            AudioQualityDetail(
                label: String(localized: "Channels"),
                value: Self.channels(path.sourceChannelCount)
            ),
            AudioQualityDetail(
                label: String(localized: "Renderer"),
                value: Self.renderer(path)
            ),
            AudioQualityDetail(
                label: String(localized: "Output"),
                value: path.outputRoute.name
            ),
            AudioQualityDetail(
                label: String(localized: "Source"),
                value: Self.source(path.sourceSpatialFormat)
            ),
            AudioQualityDetail(
                label: String(localized: "Next Track"),
                value: path.nextTransitionIsGapless
                    ? String(localized: "Gapless")
                    : String(localized: "Standard Transition")
            ),
        ]
    }

    private static func format(
        _ path: AudioPathSnapshot,
        codec: String,
        sampleRate: String
    ) -> String {
        ([codec, path.sourceBitDepth.map { "\($0)-bit" }, sampleRate]
            .compactMap(\.self))
            .joined(separator: " · ")
    }

    private static func channels(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "Mono")
        }
        if count == 2 {
            return String(localized: "Stereo")
        }
        return String(localized: "\(count) channels")
    }

    private static func renderer(_ path: AudioPathSnapshot) -> String {
        let name = switch path.backend {
        case .native: String(localized: "System Native")
        case .pcm: String(localized: "Cadence PCM")
        }
        guard let rate = path.rendererSampleRate else {
            return name
        }
        return "\(name) · \(sampleRate(rate))"
    }

    private static func source(_ format: StoredSpatialFormat) -> String {
        switch format {
        case .dolbyAtmos: String(localized: "Dolby Atmos")
        case .multichannel: String(localized: "Multichannel")
        case .stereo: String(localized: "Stereo")
        case .unknown: String(localized: "Unknown")
        }
    }

    private static func sampleRate(_ rate: Double) -> String {
        let kilohertz = rate / 1000
        return kilohertz.formatted(
            .number.precision(.fractionLength(0 ... 1))
        ) + " kHz"
    }
}
