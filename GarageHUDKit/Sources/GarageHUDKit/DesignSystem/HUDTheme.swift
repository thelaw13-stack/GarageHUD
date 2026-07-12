import SwiftUI

public enum HUDTheme {
    // MARK: Color roles (≈85% neutral / 10% accent / 5% warning)
    public static let background = Color(red: 0.02, green: 0.04, blue: 0.06)
    public static let panelBackground = Color(red: 0.055, green: 0.075, blue: 0.10)
    /// A hairline used for containment — borders indicate interactivity/containment, not merely
    /// the presence of information.
    public static let hairline = Color(white: 1.0).opacity(0.08)

    public static let cyan = Color(red: 0.0, green: 0.85, blue: 1.0)     // interactive / selected
    public static let amber = Color(red: 1.0, green: 0.66, blue: 0.15)   // attention required
    public static let danger = Color(red: 1.0, green: 0.27, blue: 0.32)  // fault / safety / critical
    public static let green = Color(red: 0.30, green: 0.82, blue: 0.50)  // financial (convention)

    // Retained for existing call sites; prefer the roles above for new work.
    public static let blue = Color(red: 0.25, green: 0.55, blue: 1.0)
    public static let purple = Color(red: 0.68, green: 0.4, blue: 1.0)

    public static let textPrimary = Color(white: 0.94)      // primary data
    public static let textSecondary = Color(white: 0.56)    // secondary / history
    public static let textTertiary = Color(white: 0.40)     // faint metadata

    // MARK: Typography — a strict four-level scale. Use weight, not new sizes, for emphasis.
    public static func monoFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    public static func title(_ weight: Font.Weight = .bold) -> Font { monoFont(30, weight: weight) }
    public static func section(_ weight: Font.Weight = .semibold) -> Font { monoFont(19, weight: weight) }
    public static func body(_ weight: Font.Weight = .regular) -> Font { monoFont(14, weight: weight) }
    public static func label(_ weight: Font.Weight = .regular) -> Font { monoFont(10, weight: weight) }

    // MARK: Spacing — the only allowed scale: 4 / 8 / 16 / 24 / 32.
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 16
    public static let space4: CGFloat = 24
    public static let space5: CGFloat = 32

    public static let cornerRadius: CGFloat = 12
    public static let panelPadding: CGFloat = 20   // a touch more air than before
}
