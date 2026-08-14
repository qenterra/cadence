import SwiftUI

struct SettingsAboutSection: View {
    private let columns = [
        GridItem(.flexible(), spacing: CadenceLayout.compactGap),
        GridItem(.flexible(), spacing: CadenceLayout.compactGap),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: CadenceLayout.compactGap) {
            creatorCard

            LazyVGrid(columns: columns, spacing: CadenceLayout.compactGap) {
                SettingsAboutLinkTile(
                    title: "GitHub Profile",
                    subtitle:
                    "More projects by \(AppConfiguration.creatorName)",
                    symbol: "person.2.circle",
                    destination: AppConfiguration.creatorURL
                )
                SettingsAboutLinkTile(
                    title: "Source Code",
                    subtitle: "Browse and contribute to Cadence",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    destination: AppConfiguration.projectURL
                )
                SettingsAboutLinkTile(
                    title: "Wiki",
                    subtitle: "Product and engineering documentation",
                    symbol: "book.pages",
                    destination: AppConfiguration.wikiURL
                )
                SettingsAboutLinkTile(
                    title: "MIT License",
                    subtitle: "Cadence source and documentation",
                    symbol: "doc.text",
                    destination: AppConfiguration.licenseURL
                )
                SettingsAboutLinkTile(
                    title: "Third-Party Notices",
                    subtitle: "Licenses for development dependencies",
                    symbol: "books.vertical",
                    destination: AppConfiguration.thirdPartyNoticesURL
                )
                SettingsAboutLinkTile(
                    title: "Buy Me a Coffee",
                    subtitle: "Support independent development",
                    symbol: "cup.and.saucer",
                    destination: AppConfiguration.supportURL
                )
            }
        }
    }

    private var creatorCard: some View {
        Link(destination: AppConfiguration.creatorURL) {
            HStack(spacing: CadenceLayout.contentGap) {
                SettingsAboutSymbol(symbol: "person.crop.circle")

                VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                    Text("Created by \(AppConfiguration.creatorName)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("© 2026 \(AppConfiguration.creatorName)")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("Version \(appVersion)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, CadenceLayout.contentGap)
            .frame(minHeight: 76)
            .background(CadenceTheme.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel))
            .overlay {
                RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel)
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel))
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
    }
}

private struct SettingsAboutLinkTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let destination: URL

    @State private var isHovered = false

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: CadenceLayout.controlGap) {
                SettingsAboutSymbol(symbol: symbol)

                VStack(alignment: .leading, spacing: CadenceLayout.textStack) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: CadenceLayout.compactGap)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, CadenceLayout.contentGap)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                isHovered
                    ? CadenceTheme.selectionFill
                    : CadenceTheme.secondarySurface
            )
            .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel))
            .overlay {
                RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel)
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusPanel))
        }
        .buttonStyle(.plain)
        .onHover {
            isHovered = $0
        }
        .accessibilityHint("Opens in your default browser")
    }
}

private struct SettingsAboutSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .frame(width: 40, height: 40)
            .background(CadenceTheme.opaqueSurface)
            .clipShape(RoundedRectangle(cornerRadius: CadenceTheme.radiusControl))
    }
}
