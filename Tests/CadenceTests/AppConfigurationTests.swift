@testable import Cadence
import Testing

struct AppConfigurationTests {
    @Test("Cadence targets the configured macOS baseline")
    func deploymentTarget() {
        #expect(AppConfiguration.minimumDeploymentTarget == "26.0")
        #expect(AppConfiguration.bundleIdentifier == "com.qenterra.cadence")
    }

    @Test("Public project links point to QenTerra-owned destinations")
    func publicLinks() {
        #expect(
            AppConfiguration.projectURL.absoluteString
                == "https://github.com/QenTerra/cadence"
        )
        #expect(
            AppConfiguration.licenseURL.absoluteString
                == "https://github.com/QenTerra/cadence/blob/main/LICENSE"
        )
        #expect(
            AppConfiguration.wikiURL.absoluteString
                == "https://github.com/QenTerra/cadence/wiki"
        )
        #expect(
            AppConfiguration.supportURL.absoluteString
                == "https://buymeacoffee.com/qenterra"
        )
    }
}
