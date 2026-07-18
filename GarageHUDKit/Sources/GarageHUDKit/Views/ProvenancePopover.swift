import SwiftUI

/// A headline figure that answers for itself: tap it and it shows where the number came from.
/// Wraps any stat view; the tap presents the figure's `FigureProvenance` in a small popover.
/// The "explain" affordance is a quiet info glyph — evidence on demand, never in the way.
struct ProvenanceTappable<Content: View>: View {
    let provenance: FigureProvenance?
    @ViewBuilder let content: () -> Content

    @State private var showing = false

    var body: some View {
        if let provenance {
            Button { showing = true } label: {
                HStack(alignment: .top, spacing: 4) {
                    content()
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(HUDTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                ProvenanceCard(provenance: provenance)
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
            .accessibilityHint("Shows where this number comes from")
        } else {
            content()
        }
    }
}

/// The evidence card itself — headline figure, then each evidence line, calmly.
struct ProvenanceCard: View {
    let provenance: FigureProvenance

    var body: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            Text(provenance.headline)
                .font(HUDTheme.body(.semibold)).foregroundStyle(HUDTheme.textPrimary)
            ForEach(Array(provenance.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(HUDTheme.textTertiary).frame(width: 3, height: 3).padding(.top, 6)
                    Text(line).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(HUDTheme.space3)
        .frame(maxWidth: 320, alignment: .leading)
        .background(HUDTheme.elevatedSurface)
    }
}
