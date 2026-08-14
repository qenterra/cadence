import SwiftUI

enum CadenceGlassSurfacePresentation: Equatable, Sendable {
    case material
    case opaque

    static func resolve(
        reduceTransparency: Bool
    ) -> Self {
        reduceTransparency ? .opaque : .material
    }
}

extension View {
    func cadenceGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(CadenceGlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}

private struct CadenceGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if CadenceGlassSurfacePresentation.resolve(
            reduceTransparency: reduceTransparency
        ) == .opaque {
            content.background(
                CadenceTheme.opaqueSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
