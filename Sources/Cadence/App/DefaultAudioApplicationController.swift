import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
protocol DefaultAudioApplicationWorkspace: AnyObject {
    func defaultApplicationURL(for contentType: UTType) -> URL?
    func setDefaultApplication(
        at applicationURL: URL,
        for contentType: UTType
    ) async throws
}

@MainActor
final class SystemDefaultAudioApplicationWorkspace:
    DefaultAudioApplicationWorkspace {
    func defaultApplicationURL(for contentType: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: contentType)
    }

    func setDefaultApplication(
        at applicationURL: URL,
        for contentType: UTType
    ) async throws {
        try await NSWorkspace.shared.setDefaultApplication(
            at: applicationURL,
            toOpen: contentType
        )
    }
}

@MainActor
@Observable
final class DefaultAudioApplicationController {
    let supportedContentTypes: [UTType]
    private let workspace: any DefaultAudioApplicationWorkspace
    private let applicationURL: URL

    private(set) var isDefaultForAllSupportedAudio = false
    private(set) var isChanging = false
    private(set) var errorMessage: String?

    init(
        workspace: any DefaultAudioApplicationWorkspace =
            SystemDefaultAudioApplicationWorkspace(),
        applicationURL: URL = Bundle.main.bundleURL
    ) {
        self.workspace = workspace
        self.applicationURL = applicationURL.standardizedFileURL
        let types = SupportedAudioFormat.supportedPathExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        supportedContentTypes = types.reduce(into: [String: UTType]()) {
            $0[$1.identifier] = $1
        }
        .values.sorted { $0.identifier < $1.identifier }
        refresh()
    }

    func refresh() {
        isDefaultForAllSupportedAudio = supportedContentTypes.allSatisfy {
            workspace.defaultApplicationURL(for: $0)?.standardizedFileURL
                == applicationURL
        }
    }

    func setCadenceAsDefault() async {
        guard !isChanging else {
            return
        }
        isChanging = true
        errorMessage = nil
        var failures: [String] = []

        for contentType in supportedContentTypes {
            do {
                try await workspace.setDefaultApplication(
                    at: applicationURL,
                    for: contentType
                )
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        refresh()
        isChanging = false
        if !failures.isEmpty {
            errorMessage = "macOS did not change every audio file association. "
                + "You can try again or set Cadence from Finder."
        }
    }
}
