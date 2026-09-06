@testable import Cadence
import CoreGraphics
import QenTerraComponents
import QenTerraDesignTokens
import QenTerraMediaComponents
import Testing

struct DesignSystemIntegrationTests {
    @Test("Cadence uses the shared product profile")
    func cadenceUsesTheSharedProductProfile() {
        let configuration = CadenceDesignSystemEnvironment.configuration(
            for: .system
        )

        #expect(configuration.productProfile == .cadence)
        #expect(configuration.density == .standard)
        #expect(
            CadenceLayout.pageInset
                == CGFloat(DesignProductMetrics.cadence.pageInset)
        )
    }

    @Test("Cadence appearance preferences map without resolving the system")
    func appearancePreferencesMapDirectly() {
        #expect(
            CadenceDesignSystemEnvironment.configuration(for: .system).appearance
                == .system
        )
        #expect(
            CadenceDesignSystemEnvironment.configuration(for: .light).appearance
                == .light
        )
        #expect(
            CadenceDesignSystemEnvironment.configuration(for: .dark).appearance
                == .dark
        )
    }
}
