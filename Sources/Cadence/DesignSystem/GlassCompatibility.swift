import SwiftUI

enum CadenceGlassSurfacePresentation: Equatable, Sendable {
    case nativeGlass
    case opaqueFallback

    static func resolve(
        usesStableSystemControls: Bool,
        reduceTransparency: Bool
    ) -> Self {
        usesStableSystemControls || reduceTransparency
            ? .opaqueFallback
            : .nativeGlass
    }
}

extension View {
    func cadenceGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(CadenceGlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}

private struct CadenceGlassSurfaceModifier: ViewModifier {
    @Environment(\.visualRegressionUsesStableSystemControls)
    private var usesStableSystemControls
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if CadenceGlassSurfacePresentation.resolve(
            usesStableSystemControls: usesStableSystemControls,
            reduceTransparency: reduceTransparency
        ) == .opaqueFallback {
            content.background(
                CadenceTheme.opaqueSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
