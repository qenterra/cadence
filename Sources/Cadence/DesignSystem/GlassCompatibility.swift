import SwiftUI

extension View {
    func cadenceGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(CadenceGlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}

private struct CadenceGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else if reduceTransparency {
            content.background(
                CadenceTheme.opaqueSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}
