import SwiftUI

public struct GlowModifier: ViewModifier {
    var color: Color
    var radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.8), radius: radius)
            .shadow(color: color.opacity(0.5), radius: radius * 2)
    }
}

public extension View {
    func hudGlow(_ color: Color = HUDTheme.cyan, radius: CGFloat = 4) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }
}
