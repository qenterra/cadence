@testable import Cadence
import Testing

struct AppConfigurationTests {
    @Test("Cadence targets the configured macOS baseline")
    func deploymentTarget() {
        #expect(AppConfiguration.minimumDeploymentTarget == "15.0")
        #expect(AppConfiguration.bundleIdentifier == "com.qenterra.cadence")
    }
}
