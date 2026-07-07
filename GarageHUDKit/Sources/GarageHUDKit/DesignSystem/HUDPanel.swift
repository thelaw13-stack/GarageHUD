import SwiftUI

public struct HUDPanel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(HUDTheme.monoFont(11, weight: .semibold))
                    .foregroundStyle(HUDTheme.cyan)
                    .tracking(2)
            }
            content
        }
        .padding(HUDTheme.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: HUDTheme.cornerRadius)
                .fill(HUDTheme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HUDTheme.cornerRadius)
                .strokeBorder(HUDTheme.cyan.opacity(0.35), lineWidth: 1)
        )
        .hudGlow(HUDTheme.cyan.opacity(0.15), radius: 8)
    }
}

public extension View {
    /// Renders as a checkbox on macOS (where it reads naturally in a list) and a switch on iOS,
    /// since `.checkbox` toggle style doesn't exist there.
    @ViewBuilder
    func hudCheckboxStyle() -> some View {
        #if os(macOS)
        self.toggleStyle(.checkbox)
        #else
        self.toggleStyle(.switch)
        #endif
    }
}

public struct HUDButtonStyle: ButtonStyle {
    var color: Color

    public init(color: Color = HUDTheme.cyan) {
        self.color = color
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HUDTheme.monoFont(12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(configuration.isPressed ? 0.25 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(color.opacity(0.6), lineWidth: 1)
            )
            .hudGlow(color.opacity(configuration.isPressed ? 0.5 : 0.2), radius: 4)
    }
}
