@testable import Cadence
import Testing

struct AppConfigurationTests {
    @Test("Unit-test hosts never open the current user's library")
    func hostUsesPreviewLibrary() {
        let testEnvironment = [
            "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
        ]

        #expect(
            CadenceLaunchEnvironment.shouldUsePreviewLibrary(
                environment: testEnvironment
            )
        )
        #expect(
            !CadenceLaunchEnvironment.shouldEnforceSingleInstance(
                environment: testEnvironment
            )
        )
        #expect(
            !CadenceLaunchEnvironment.shouldUsePreviewLibrary(
                environment: [:]
            )
        )
        #expect(
            CadenceLaunchEnvironment.shouldEnforceSingleInstance(
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
            AppConfiguration.updateFeedURL.absoluteString
                == "https://raw.githubusercontent.com/QenTerra/cadence/main/appcast.xml"
        )
    }

    @Test("Stable updates exclude prereleases unless beta updates are enabled")
    func updateChannelPolicy() {
        #expect(
            CadenceUpdateChannelPolicy.allowedChannels(
                includesBetaUpdates: false
            ).isEmpty
        )
        #expect(
            CadenceUpdateChannelPolicy.allowedChannels(
                includesBetaUpdates: true
            ) == Set(["beta"])
        )
    }
}
