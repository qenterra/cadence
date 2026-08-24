import SwiftUI

struct CadenceModeHint: View {
    static let copy = "Z + X — Cadence Mode"
    static let accessibilityCopy = "Z plus X, Cadence Mode"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                keycap("Z")
                Text(verbatim: "+")
                keycap("X")
                Text(verbatim: "— Cadence Mode")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(CadenceTheme.subduedFill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help("Enter Cadence Mode")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.accessibilityCopy))
    }

    private func keycap(_ key: String) -> some View {
        Text(verbatim: key)
            .font(.caption.monospaced().weight(.semibold))
            .frame(minWidth: 20, minHeight: 18)
            .padding(.horizontal, 3)
            .background(CadenceTheme.subduedFill)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusControl,
                    style: .continuous
                )
            )
    }
}
