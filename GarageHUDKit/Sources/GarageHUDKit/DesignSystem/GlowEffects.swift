import SwiftUI

public struct GlowModifier: ViewModifier {
    var color: Color
    var radius: CGFloat

    // Restrained: a single soft shadow. Reserve any glow for active controls, live states, or
    // truly important alerts — never as ambient decoration.
    public func body(content: Content) -> some View {
        content.shadow(color: color.opacity(0.45), radius: radius)
    }
}

public extension View {
    func hudGlow(_ color: Color = HUDTheme.cyan, radius: CGFloat = 4) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }
}
