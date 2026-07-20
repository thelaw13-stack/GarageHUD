import SwiftUI

/// The shape of a car hero band across every window size (W-067 follow-up).
///
/// A fixed height over an unbounded width worked on the phone but degenerated on a wide desktop
/// window: at fullscreen the band became a thin wide strip, so a fitted photo shrank into a sea of
/// blur and a filled one cropped hard. This keeps the band a consistent banner *shape* instead —
/// capped in width and centred with margins on a large window — so the car reads the same whether
/// the window is small or maximised.
///
/// Compact width (iPhone) keeps the familiar fixed height; the aspect treatment is a
/// regular-width / desktop concern.
public struct HeroBandShape: ViewModifier {
    let compact: Bool

    /// Widest the hero is allowed to get — beyond this it centres with margins rather than stretch.
    private let maxWidth: CGFloat = 960
    /// Banner proportion (width : height). A wide, letterbox-free car shape.
    private let aspect: CGFloat = 2.4

    public init(compact: Bool) { self.compact = compact }

    public func body(content: Content) -> some View {
        if compact {
            content.frame(maxWidth: .infinity).frame(height: 176)
        } else {
            // A clear spacer carries the aspect ratio and sizes to the available (capped) width; the
            // photo overlays it. The outer max-width:∞ centres the capped band within the window.
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(content)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
