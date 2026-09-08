@testable import Cadence
import Foundation
import QenTerraComponents
import Testing

struct CadenceAboutConfigurationTests {
    @Test("About adapter supplies every Cadence-owned value")
    func suppliesProductValues() throws {
        let bundle = try makeBundle(version: "0.2.0", build: "2")
        let configuration = CadenceAboutConfiguration.make(bundle: bundle)

        #expect(configuration.applicationName == "Cadence")
        #expect(configuration.versionText == "Version 0.2.0 (2)")
        #expect(configuration.creatorText == "Created by \(AppConfiguration.creatorName)")
        #expect(configuration.resources.map(\.title) == [
            "GitHub Profile",
            "Source Code",
            "Wiki",
            "MIT License",
            "Third-Party Notices",
        ])
        #expect(configuration.resources.allSatisfy { $0.destination.scheme == "https" })
    }

    @Test("About adapter fails closed to declared product fallbacks")
    func suppliesVersionFallbacks() throws {
        let bundle = try makeBundle(version: nil, build: nil)
        let configuration = CadenceAboutConfiguration.make(bundle: bundle)

        #expect(configuration.versionText == "Version 0.1.0 (1)")
    }

    private func makeBundle(version: String?, build: String?) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CadenceAbout-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        var plist: [String: Any] = [
            "CFBundleIdentifier": "com.qenterra.cadence.tests.about",
        ]
        plist["CFBundleShortVersionString"] = version
        plist["CFBundleVersion"] = build
        try (plist as NSDictionary).write(
            to: root.appending(path: "Info.plist")
        )
        return try #require(Bundle(url: root))
    }
}
