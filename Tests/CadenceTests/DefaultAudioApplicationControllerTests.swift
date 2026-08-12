@testable import Cadence
import Foundation
import Testing
import UniformTypeIdentifiers

@MainActor
struct DefaultAudioApplicationControllerTests {
    @Test("Cadence is registered for every supported audio content type")
    func setsEverySupportedType() async {
        let applicationURL = URL(filePath: "/Applications/Cadence.app")
        let workspace = DefaultAudioWorkspaceSpy()
        let controller = DefaultAudioApplicationController(
            workspace: workspace,
            applicationURL: applicationURL
        )

        await controller.setCadenceAsDefault()

        let expectedIdentifiers = Set(
            SupportedAudioFormat.supportedPathExtensions.compactMap {
                UTType(filenameExtension: $0)?.identifier
            }
        )
        #expect(Set(workspace.requestedIdentifiers) == expectedIdentifiers)
        #expect(controller.isDefaultForAllSupportedAudio)
        #expect(controller.errorMessage == nil)
    }

    @Test("A failed type is reported after every type was attempted")
    func reportsPartialFailure() async throws {
        let applicationURL = URL(filePath: "/Applications/Cadence.app")
        let failedIdentifier = try #require(
            UTType(filenameExtension: "mp3")?.identifier
        )
        let workspace = DefaultAudioWorkspaceSpy(
            failedIdentifiers: [failedIdentifier]
        )
        let controller = DefaultAudioApplicationController(
            workspace: workspace,
            applicationURL: applicationURL
        )

        await controller.setCadenceAsDefault()

        #expect(
            Set(workspace.requestedIdentifiers).count
                == controller.supportedContentTypes.count
        )
        #expect(!controller.isDefaultForAllSupportedAudio)
        #expect(controller.errorMessage != nil)
    }
}

@MainActor
private final class DefaultAudioWorkspaceSpy: DefaultAudioApplicationWorkspace {
    private let failedIdentifiers: Set<String>
    private var defaults: [String: URL] = [:]
    private(set) var requestedIdentifiers: [String] = []

    init(failedIdentifiers: Set<String> = []) {
        self.failedIdentifiers = failedIdentifiers
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? {
        defaults[contentType.identifier]
    }

    func setDefaultApplication(
        at applicationURL: URL,
        for contentType: UTType
    ) async throws {
        requestedIdentifiers.append(contentType.identifier)
        if failedIdentifiers.contains(contentType.identifier) {
            throw DefaultAudioWorkspaceTestError.denied
        }
        defaults[contentType.identifier] = applicationURL
    }
}

private enum DefaultAudioWorkspaceTestError: Error {
    case denied
}
