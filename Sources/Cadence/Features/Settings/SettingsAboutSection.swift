import AppKit
import SwiftUI

struct SettingsAboutResource: Identifiable {
    let title: String
    let subtitle: String
    let symbol: String
    let destination: URL

    var id: String {
        title
    }
}

enum SettingsAboutContent {
    static let usesProductHero = true
    static let resources = [
        SettingsAboutResource(
            title: "GitHub Profile",
            subtitle: "More projects by \(AppConfiguration.creatorName)",
            symbol: "person.crop.circle",
            destination: AppConfiguration.creatorURL
        ),
        SettingsAboutResource(
            title: "Source Code",
            subtitle: "Browse and contribute to Cadence",
            symbol: "chevron.left.forwardslash.chevron.right",
            destination: AppConfiguration.projectURL
        ),
        SettingsAboutResource(
            title: "Wiki",
            subtitle: "Product and engineering documentation",
            symbol: "book.pages",
            destination: AppConfiguration.wikiURL
        ),
        SettingsAboutResource(
            title: "MIT License",
            subtitle: "Cadence source and documentation",
            symbol: "doc.text",
            destination: AppConfiguration.licenseURL
        ),
        SettingsAboutResource(
            title: "Third-Party Notices",
            subtitle: "Licenses for bundled dependencies",
            symbol: "books.vertical",
            destination: AppConfiguration.thirdPartyNoticesURL
        ),
    ]

    static var resourceTitles: [String] {
        resources.map(\.title)
    }
}

struct SettingsAboutSection: View {
    var body: some View {
        VStack(spacing: SettingsLayoutMetrics.sectionSpacing) {
            productHero

            SettingsCard(title: "Resources", symbol: "link") {
                VStack(spacing: 0) {
                    ForEach(
                        Array(SettingsAboutContent.resources.enumerated()),
                        id: \.element.id
                    ) { index, resource in
                        SettingsAboutResourceRow(resource: resource)

                        if index < SettingsAboutContent.resources.count - 1 {
                            Divider()
                                .padding(.leading, 38)
                        }
                    }
                }
            }
        }
    }

    private var productHero: some View {
        VStack(alignment: .leading, spacing: CadenceLayout.contentGap) {
            HStack(spacing: CadenceLayout.contentGap) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: CadenceTheme.radiusPanel,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                    Text("Cadence")
                        .font(.title2.weight(.semibold))

                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text("Native music, kept focused.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text(
                "A focused macOS music library built for local collections, "
                    + "careful metadata, and uninterrupted listening."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Label(
                    "Created by \(AppConfiguration.creatorName)",
                    systemImage: "person.crop.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text("© 2026 QenTerra")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(SettingsLayoutMetrics.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CadenceTheme.secondarySurface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: CadenceTheme.radiusPanel,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: CadenceTheme.radiusPanel,
                style: .continuous
            )
            .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
        }
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
    }
}

private struct SettingsAboutResourceRow: View {
    let resource: SettingsAboutResource
    @State private var isHovered = false

    var body: some View {
        Link(destination: resource.destination) {
            HStack(spacing: CadenceLayout.controlGap) {
                Image(systemName: resource.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)

                VStack(
                    alignment: .leading,
                    spacing: CadenceLayout.textStack
                ) {
                    Text(LocalizedStringKey(resource.title))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(LocalizedStringKey(resource.subtitle))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: CadenceLayout.compactGap)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, CadenceLayout.compactGap)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                isHovered ? CadenceTheme.hoverFill : Color.clear,
                in: RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusControl,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityHint("Opens in your default browser")
    }
}
