import SwiftUI

public enum HUDTheme {
    public static let background = Color(red: 0.02, green: 0.04, blue: 0.06)
    public static let panelBackground = Color(red: 0.05, green: 0.08, blue: 0.11)
    public static let cyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    public static let amber = Color(red: 1.0, green: 0.62, blue: 0.11)
    public static let danger = Color(red: 1.0, green: 0.25, blue: 0.3)
    public static let blue = Color(red: 0.25, green: 0.55, blue: 1.0)
    public static let green = Color(red: 0.25, green: 0.85, blue: 0.45)
    public static let purple = Color(red: 0.68, green: 0.4, blue: 1.0)
    public static let textPrimary = Color(white: 0.92)
    public static let textSecondary = Color(white: 0.55)

    public static func monoFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static let cornerRadius: CGFloat = 10
    public static let panelPadding: CGFloat = 16
}
