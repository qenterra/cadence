import Foundation
import QenTerraComponents

enum CadenceAboutConfiguration {
    static func make(
        bundle: Bundle = .main,
        resources: [AboutResource]? = nil
    ) -> AboutPageConfiguration {
        let version = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
        let build = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"

        return AboutPageConfiguration(
            applicationName: "Cadence",
            tagline: "Native music, kept focused.",
            description: "A focused macOS music library built for local collections, "
                + "careful metadata, and uninterrupted listening.",
            versionText: "Version \(version) (\(build))",
            creatorText: "Created by \(AppConfiguration.creatorName)",
            copyrightText: "© 2026 QenTerra",
            resourcesTitle: "Resources",
            resources: resources ?? defaultResources
        )
    }

    private static let defaultResources = [
        resource(
            id: "creator",
            title: "GitHub Profile",
            subtitle: "More projects by \(AppConfiguration.creatorName)",
            symbol: "person.crop.circle",
            destination: AppConfiguration.creatorURL
        ),
        resource(
            id: "source",
            title: "Source Code",
            subtitle: "Browse and contribute to Cadence",
            symbol: "chevron.left.forwardslash.chevron.right",
            destination: AppConfiguration.projectURL
        ),
        resource(
            id: "wiki",
            title: "Wiki",
            subtitle: "Product and engineering documentation",
            symbol: "book.pages",
            destination: AppConfiguration.wikiURL
        ),
        resource(
            id: "license",
            title: "MIT License",
            subtitle: "Cadence source and documentation",
            symbol: "doc.text",
            destination: AppConfiguration.licenseURL
        ),
        resource(
            id: "third-party-notices",
            title: "Third-Party Notices",
            subtitle: "Licenses for bundled dependencies",
            symbol: "books.vertical",
            destination: AppConfiguration.thirdPartyNoticesURL
        ),
    ]

    private static func resource(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        destination: URL
    ) -> AboutResource {
        precondition(destination.scheme == "https")
        return AboutResource(
            id: id,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            destination: destination,
            accessibilityHint: "Opens in your default browser"
        )
    }
}
