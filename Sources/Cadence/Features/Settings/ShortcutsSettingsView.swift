import SwiftUI

struct ShortcutReference: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let keys: [ShortcutKey]
}

enum ShortcutKey: String, Identifiable, Equatable, Sendable {
    case command
    case shift
    case space
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case `return`
    case delete
    case click

    var id: String {
        rawValue
    }

    var glyph: String {
        switch self {
        case .command: "⌘"
        case .shift: "⇧"
        case .space: "Space"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .return: "↩"
        case .delete: "⌫"
        case .click: "Click"
        }
    }

    var symbolName: String? {
        switch self {
        case .space: "space"
        case .leftArrow: "arrow.left"
        case .rightArrow: "arrow.right"
        case .upArrow: "arrow.up"
        case .downArrow: "arrow.down"
        case .return: "return"
        case .delete: "delete.left"
        case .click: "cursorarrow.click"
        case .command, .shift: nil
        }
    }
}

enum ShortcutCatalog {
    static let entries = [
        ShortcutReference(
            id: "play-pause",
            title: "Play or Pause",
            keys: [.space]
        ),
        ShortcutReference(
            id: "previous",
            title: "Previous Track",
            keys: [.command, .leftArrow]
        ),
        ShortcutReference(
            id: "next",
            title: "Next Track",
            keys: [.command, .rightArrow]
        ),
        ShortcutReference(
            id: "volume-up",
            title: "Volume Up",
            keys: [.command, .upArrow]
        ),
        ShortcutReference(
            id: "volume-down",
            title: "Volume Down",
            keys: [.command, .downArrow]
        ),
        ShortcutReference(
            id: "play-selection",
            title: "Play Selected Track",
            keys: [.return]
        ),
        ShortcutReference(
            id: "range-selection",
            title: "Extend Selection",
            keys: [.shift, .click]
        ),
        ShortcutReference(
            id: "toggle-selection",
            title: "Toggle Selection",
            keys: [.command, .click]
        ),
        ShortcutReference(
            id: "remove-selection",
            title: "Remove Selected Tracks",
            keys: [.delete]
        ),
    ]
}

struct ShortcutsSettingsView: View {
    var body: some View {
        SettingsCard(
            title: "Shortcuts",
            symbol: "keyboard"
        ) {
            VStack(spacing: 0) {
                ForEach(ShortcutCatalog.entries) { shortcut in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(shortcut.title)
                        Spacer(minLength: 16)
                        ShortcutKeyGlyphs(keys: shortcut.keys)
                    }
                    .padding(.vertical, 9)

                    if shortcut.id != ShortcutCatalog.entries.last?.id {
                        Divider()
                    }
                }
            }
            .accessibilityElement(children: .contain)

            Text(
                "Text fields, menus, sheets, and editors keep their local keyboard behavior."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutKeyGlyphs: View {
    let keys: [ShortcutKey]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys) { key in
                Group {
                    if let symbolName = key.symbolName {
                        Image(systemName: symbolName)
                    } else {
                        Text(key.glyph)
                    }
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 5)
                .background(CadenceTheme.subduedFill)
                .clipShape(
                    RoundedRectangle(cornerRadius: CadenceTheme.radiusControl)
                )
                .accessibilityLabel(key.glyph)
            }
        }
    }
}
