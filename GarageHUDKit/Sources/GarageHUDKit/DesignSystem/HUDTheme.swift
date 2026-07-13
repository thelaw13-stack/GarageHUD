import SwiftUI

public enum HUDTheme {
    // MARK: Palette — dark neutral cockpit, restrained signal color, the car/photo as the
    // emotional color. Exact values are the GarageHUD design-language spec (hex in comments).
    // Rule: cyan is an instrument light, not wallpaper.
    public static let background = Color(hex: 0x050A0F)        // Deep Garage — app background
    public static let panelBackground = Color(hex: 0x0E131A)   // Instrument Black — quiet panels
    public static let elevatedSurface = Color(hex: 0x141B24)   // Graphite Glass — identity/active surfaces
    /// Ghost Line — a hairline for containment; borders indicate interactivity/containment, not
    /// merely the presence of information.
    public static let hairline = Color(white: 1.0).opacity(0x14 / 255.0)   // #FFFFFF14

    public static let cyan = Color(hex: 0x00D9FF)     // Electric Cyan — interactive / selected / measured
    public static let amber = Color(hex: 0xFFA826)    // Service Amber — due soon / review needed
    public static let danger = Color(hex: 0xFF454F)   // Fault Red — overdue / safety / critical
    public static let green = Color(hex: 0x4DD17F)    // System Green — operational / synced / complete

    // Retained for existing call sites; prefer the roles above for new work.
    public static let blue = Color(red: 0.25, green: 0.55, blue: 1.0)
    public static let purple = Color(red: 0.68, green: 0.4, blue: 1.0)

    public static let textPrimary = Color(hex: 0xEFF2F4)    // Warm White — primary readable data
    public static let textSecondary = Color(hex: 0x8D959E)  // Cool Gray — metadata / evidence / subtitles
    public static let textTertiary = Color(hex: 0x666E78)   // Dim Steel — timestamps / quiet labels

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

public extension Color {
    /// Build a color from a 0xRRGGBB literal so the palette reads as the spec's hex values.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0)
    }
}
