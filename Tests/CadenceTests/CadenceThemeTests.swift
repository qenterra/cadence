@testable import Cadence
import Foundation
import QenTerraDesignTokens
import Testing

struct CadenceThemeTests {
    @Test("Cadence theme is backed by the connected QDS package")
    func qdsPackageContract() {
        #expect(CadenceTheme.qdsVersion == QDS.version)
        #expect(QDS.version == "4.2.0")
    }

    @Test("Player controls keep accessible contrast in both appearances")
    func playerControlContrast() throws {
        for appearance in QDSAppearance.allCases {
            let surface = try RGBColor(
                source: QDS.Color.surfaceContent.value(for: appearance)
            )
            for state in PlayerControlVisualState.allCases {
                let foreground = try RGBColor(
                    source: state.token.value(for: appearance)
                )
                #expect(
                    foreground.contrastRatio(against: surface) >= 4.5,
                    "\(state) must stay readable in \(appearance)"
                )
            }
        }
    }

    @Test("The player bar gives neutral guidance without duplicating import")
    func emptyPlayerPresentation() {
        let empty = PlayerBarEmptyPresentation(libraryTrackCount: 0)
        let populated = PlayerBarEmptyPresentation(libraryTrackCount: 12)

        #expect(empty.title == "Open an audio file to listen")
        #expect(empty.symbolName == "waveform")
        #expect(populated.title == "Select a Track")
        #expect(populated.symbolName == "music.note")
    }
}

private struct RGBColor {
    let red: Double
    let green: Double
    let blue: Double

    init(source: String) throws {
        guard source.hasPrefix("#"), source.count == 7,
              let value = UInt64(source.dropFirst(), radix: 16)
        else {
            throw RGBColorError.unsupported(source)
        }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    func contrastRatio(against other: Self) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * linearized(red)
            + 0.7152 * linearized(green)
            + 0.0722 * linearized(blue)
    }

    private func linearized(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }
}

private enum RGBColorError: Error {
    case unsupported(String)
}
