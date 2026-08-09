@testable import Cadence
import QenTerraDesignTokens
import Testing

struct CadenceThemeTests {
    @Test("Cadence theme is backed by the connected QDS package")
    func qdsPackageContract() {
        #expect(CadenceTheme.qdsVersion == QDS.version)
        #expect(QDS.version == "1.10.0")
    }
}
