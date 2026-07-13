import SwiftUI

/// One shared button vocabulary so the same action type looks identical everywhere. Prefer
/// these over bespoke padded/outlined labels. All non-compact variants meet the 44pt touch
/// target; color follows the design system's role meanings (cyan = interaction, amber =
/// attention, red = destructive, neutral = secondary).
public struct ActionButton: ButtonStyle {
    public enum Kind { case primary, secondary, attention, destructive, compact }
    let kind: Kind
    public init(_ kind: Kind) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        let compact = kind == .compact
        configuration.label
            .font(compact ? HUDTheme.label(.semibold) : HUDTheme.body(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? HUDTheme.space2 : HUDTheme.space3)
            .padding(.vertical, compact ? 6 : HUDTheme.space2)
            .frame(minHeight: compact ? 28 : 44)          // iOS touch target
            .background(RoundedRectangle(cornerRadius: HUDTheme.space2).fill(tint.opacity(fillOpacity)))
            .overlay(RoundedRectangle(cornerRadius: HUDTheme.space2)
                .strokeBorder(tint.opacity(configuration.isPressed ? 0.7 : 0.45), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeInOut(duration: 0.18), value: configuration.isPressed)
    }

    private var tint: Color {
        switch kind {
        case .primary, .compact: return HUDTheme.cyan
        case .secondary: return HUDTheme.textSecondary
        case .attention: return HUDTheme.amber
        case .destructive: return HUDTheme.danger
        }
    }
    private var fillOpacity: Double { kind == .primary ? 0.12 : 0.0 }
}

public extension ButtonStyle where Self == ActionButton {
    static var primaryAction: ActionButton { ActionButton(.primary) }
    static var secondaryAction: ActionButton { ActionButton(.secondary) }
    static var attentionAction: ActionButton { ActionButton(.attention) }
    static var destructiveAction: ActionButton { ActionButton(.destructive) }
    static var compactAction: ActionButton { ActionButton(.compact) }
}
