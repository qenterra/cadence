import Foundation

enum AppConfiguration {
    static let bundleIdentifier = "com.qenterra.cadence"
    static let minimumDeploymentTarget = "26.0"
    static let creatorName = "Nikita Melnychenko (QenTerra)"
    static let projectURL = URL(string: "https://github.com/QenTerra/cadence")!
    static let creatorURL = URL(string: "https://github.com/QenTerra")!
    static let licenseURL = projectURL.appending(path: "blob/main/LICENSE")
    static let thirdPartyNoticesURL = projectURL.appending(
        path: "blob/main/THIRD_PARTY_NOTICES.md"
    )
    static let wikiURL = projectURL.appending(path: "wiki")
    static let supportURL = URL(
        string: "https://buymeacoffee.com/qenterra"
    )!
}
