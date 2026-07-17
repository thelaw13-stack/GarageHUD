import SwiftUI

/// Intentional artwork for vehicles that do not have bundled/restored photos yet.
/// Keeps the garage readable on fresh installs instead of showing blank placeholders.
struct VehicleVisualFallback: View {
    enum Style {
        case hero
        case thumbnail
    }

    var vehicle: Vehicle?
    var style: Style = .hero

    private var accent: Color {
        guard let vehicle else { return HUDTheme.cyan }
        switch abs(vehicle.id.hashValue) % 5 {
        case 0: return HUDTheme.amber
        case 1: return HUDTheme.cyan
        case 2: return HUDTheme.green
        case 3: return HUDTheme.danger
        default: return HUDTheme.blue
        }
    }

    private var initials: String {
        guard let vehicle else { return "GH" }
        let source = vehicle.nickname.isEmpty ? vehicle.make + " " + vehicle.model : vehicle.nickname
        let pieces = source.split(separator: " ")
        let letters = pieces.prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "GH" : letters.uppercased()
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = style == .thumbnail
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                background

                if compact {
                    thumbnailMark(size: side)
                } else {
                    heroMark(size: side)
                }
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    HUDTheme.panelBackground,
                    HUDTheme.elevatedSurface,
                    accent.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: style == .thumbnail ? 10 : 18) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(HUDTheme.hairline)
                        .frame(height: 1)
                }
            }
            .rotationEffect(.degrees(-16))
            .opacity(style == .thumbnail ? 0.45 : 0.72)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, HUDTheme.background.opacity(0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private func heroMark(size: CGFloat) -> some View {
        ZStack {
            // Bay number sits top-LEFT, clear of the top-right open-arrow the garage spotlight
            // overlays in this same corner (DD-001 F4 — the two used to collide).
            Text("BAY \(vehicle?.garageSlot ?? 0)")
                .font(HUDTheme.label(.semibold))
                .tracking(1.4)
                .foregroundStyle(accent.opacity(0.72))
                .padding(.leading, HUDTheme.space5)
                .padding(.top, HUDTheme.space5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .trailing, spacing: HUDTheme.space2) {
                Text(initials)
                    .font(HUDTheme.monoFont(72, weight: .black))
                    .foregroundStyle(HUDTheme.textPrimary.opacity(0.14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(vehicle?.drivetrain.rawValue.uppercased() ?? "GARAGE")
                    .font(HUDTheme.label(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(HUDTheme.textTertiary)
            }
            .padding(.trailing, HUDTheme.space5)
            .padding(.top, HUDTheme.space5 * 2)   // clear the arrow button, then the watermark below
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            Image(systemName: "car.side.fill")
                .font(.system(size: min(176, size * 0.48), weight: .light))
                .foregroundStyle(accent.opacity(0.34))
                .padding(.trailing, HUDTheme.space5)
                .padding(.bottom, HUDTheme.space5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func thumbnailMark(size: CGFloat) -> some View {
        ZStack {
            Image(systemName: "car.side.fill")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(accent.opacity(0.86))
            Text(initials)
                .font(HUDTheme.monoFont(max(9, size * 0.17), weight: .bold))
                .foregroundStyle(HUDTheme.textPrimary.opacity(0.82))
                .padding(.top, size * 0.48)
        }
    }
}
