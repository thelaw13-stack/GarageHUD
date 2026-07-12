import SwiftUI

public struct HUDPanel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space3) {
            if let title {
                // Section header: restrained, not a glowing accent. Hierarchy comes from
                // weight and the faint tint, not brightness.
                Text(title.uppercased())
                    .font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .tracking(1.5)
            }
            content
        }
        .padding(HUDTheme.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HUDTheme.cornerRadius)
                .fill(HUDTheme.panelBackground)
        )
        // A single hairline for containment — no bright border, no ambient glow.
        .overlay(
            RoundedRectangle(cornerRadius: HUDTheme.cornerRadius)
                .strokeBorder(HUDTheme.hairline, lineWidth: 1)
        )
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
            .font(HUDTheme.body(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, HUDTheme.space3)
            .padding(.vertical, HUDTheme.space2)
            .background(
                RoundedRectangle(cornerRadius: HUDTheme.space2)
                    .fill(color.opacity(configuration.isPressed ? 0.22 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HUDTheme.space2)
                    .strokeBorder(color.opacity(configuration.isPressed ? 0.7 : 0.45), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.18), value: configuration.isPressed)
    }
}
