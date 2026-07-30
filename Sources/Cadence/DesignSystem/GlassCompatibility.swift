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
        if reduceTransparency {
            content.background(
                CadenceTheme.opaqueSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
