import SwiftUI

struct ShortcutReference: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let keys: String
    let keywords: String
}

enum ShortcutCatalog {
    static let entries = [
        ShortcutReference(
            id: "play-pause",
            title: "Play or Pause",
            keys: "Space",
            keywords: "play pause space media key"
        ),
        ShortcutReference(
            id: "previous",
            title: "Previous Track",
            keys: "Command Left Arrow",
            keywords: "previous command left media key"
        ),
        ShortcutReference(
            id: "next",
            title: "Next Track",
            keys: "Command Right Arrow",
            keywords: "next command right media key"
        ),
        ShortcutReference(
            id: "volume-up",
            title: "Volume Up",
            keys: "Command Up Arrow",
            keywords: "volume command up"
        ),
        ShortcutReference(
            id: "volume-down",
            title: "Volume Down",
            keys: "Command Down Arrow",
            keywords: "volume command down"
        ),
        ShortcutReference(
            id: "play-selection",
            title: "Play Selected Track",
            keys: "Return",
            keywords: "play selected return"
        ),
        ShortcutReference(
            id: "range-selection",
            title: "Extend Selection",
            keys: "Shift-click",
            keywords: "multiple range selection shift click"
        ),
        ShortcutReference(
            id: "toggle-selection",
            title: "Toggle Selection",
            keys: "Command-click",
            keywords: "multiple additive selection command click"
        ),
        ShortcutReference(
            id: "remove-selection",
            title: "Remove Selected Tracks",
            keys: "Delete",
            keywords: "remove delete selected trash playlist queue"
        ),
    ]

    static func search(
        _ query: String
    ) -> [ShortcutReference] {
        let normalized = SearchNormalizer.normalize(query)
        guard !normalized.isEmpty else {
            return entries
        }
        return entries.filter { entry in
            SearchNormalizer.normalize(
                "\(entry.title) \(entry.keys) \(entry.keywords)"
            )
            .contains(normalized)
        }
    }
}

struct ShortcutsSettingsView: View {
    @State private var query = ""

    var body: some View {
        SettingsCard(
            title: "Shortcuts",
            symbol: "keyboard"
        ) {
            TextField("Search Shortcuts", text: $query)
                .textFieldStyle(.roundedBorder)

            let matches = ShortcutCatalog.search(query)
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(matches) { shortcut in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(shortcut.title)
                            Spacer(minLength: 16)
                            Text(shortcut.keys)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 9)

                        if shortcut.id != matches.last?.id {
                            Divider()
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }

            Text(
                "Text fields, menus, sheets, and editors keep their local keyboard behavior."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
