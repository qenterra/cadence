@testable import Cadence
import Testing

struct AppConfigurationTests {
    @Test("Unit-test hosts never open the current user's library")
    func hostUsesPreviewLibrary() {
        #expect(
            CadenceLaunchEnvironment.shouldUsePreviewLibrary(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            )
        )
        #expect(
            !CadenceLaunchEnvironment.shouldUsePreviewLibrary(
                environment: [:]
            )
        )
    }

    @Test("Cadence targets the configured macOS baseline")
    func deploymentTarget() {
        #expect(AppConfiguration.minimumDeploymentTarget == "26.0")
        #expect(AppConfiguration.bundleIdentifier == "com.qenterra.cadence")
    }

    @Test("Public project links point to QenTerra-owned destinations")
    func publicLinks() {
        #expect(
            AppConfiguration.creatorName
                == "Nikita Melnychenko (QenTerra)"
        )
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
            AppConfiguration.thirdPartyNoticesURL.absoluteString
                == "https://github.com/QenTerra/cadence/blob/main/THIRD_PARTY_NOTICES.md"
        )
        #expect(
            AppConfiguration.supportURL.absoluteString
                == "https://buymeacoffee.com/qenterra"
        )
    }
}
