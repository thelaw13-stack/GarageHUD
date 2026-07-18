import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// The vehicle biography as a polished, shareable PDF — the same `BiographyModel` words the
/// text export prints, set in the cockpit design system. One model, two inks: this view adds
/// styling only, never strings.
public enum BiographyPDF {
    /// US-Letter width; height hugs the content into a single continuous page. Very long
    /// sections are capped with a disclosed truncation (see `BiographySheetDocument`) so a
    /// decade of timeline can't push the page past the CGContext ceiling.
    @MainActor
    public static func data(for vehicle: Vehicle, pageWidth: CGFloat = 612) -> Data? {
        let doc = BiographySheetDocument(model: BiographyExporter.model(for: vehicle))
            .frame(width: pageWidth)
        let renderer = ImageRenderer(content: doc)
        renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        var result: Data?
        renderer.render { size, renderInContext in
            let mutable = NSMutableData()
            guard let consumer = CGDataConsumer(data: mutable as CFMutableData) else { return }
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            result = mutable as Data
        }
        return result
    }
}

/// A shareable biography. Defers the (main-actor) PDF render until a destination is chosen, and
/// fails loudly rather than handing over a 0-byte file.
public struct SharableBiographySheet: Transferable, Sendable {
    public enum RenderError: Error { case renderFailed }

    public let fileName: String   // without extension
    public let vehicle: Vehicle

    public init(vehicle: Vehicle) {
        self.fileName = "\(vehicle.displayName) biography"
        self.vehicle = vehicle
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { sheet in
            guard let data = await MainActor.run(body: { BiographyPDF.data(for: sheet.vehicle) }),
                  !data.isEmpty else {
                throw RenderError.renderFailed
            }
            return data
        }
        .suggestedFileName { "\($0.fileName).pdf" }
    }
}

// MARK: - The document

struct BiographySheetDocument: View {
    let model: BiographyModel

    /// Per-section line cap for the single-page PDF. A long life (hundreds of timeline events)
    /// must not push the page past the 14,400pt CGContext ceiling; the cut is disclosed on the
    /// page and the text export always carries the full history.
    static let sectionLineCap = 48

    var body: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space4) {
            header
            ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
                sectionView(section)
            }
            footer
        }
        .padding(HUDTheme.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HUDTheme.background)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.headerLines.first ?? "").font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.cyan).tracking(3)
                Spacer()
            }
            ForEach(Array(model.headerLines.dropFirst().enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == 0 ? HUDTheme.title() : HUDTheme.body())
                    .foregroundStyle(index == 0 ? HUDTheme.textPrimary : HUDTheme.textSecondary)
            }
            Rectangle().fill(HUDTheme.cyan.opacity(0.6)).frame(height: 2)
        }
    }

    private func sectionView(_ section: BiographyModel.Section) -> some View {
        let capped = Array(section.lines.prefix(Self.sectionLineCap))
        let omitted = section.lines.count - capped.count
        return VStack(alignment: .leading, spacing: HUDTheme.space1) {
            Text(section.title.uppercased()).font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textTertiary).tracking(1.5)
            ForEach(Array(capped.enumerated()), id: \.offset) { _, line in
                Text(line).font(HUDTheme.body()).foregroundStyle(HUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if omitted > 0 {
                Text("… and \(omitted) more — the full history is in the text export.")
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
            }
        }
        .padding(HUDTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.elevatedSurface))
    }

    private var footer: some View {
        HStack {
            Text(model.footer).font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
            Spacer()
            Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                .font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
        }
    }
}
