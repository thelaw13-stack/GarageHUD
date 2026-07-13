import SwiftUI

struct BulkImportPartsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle

    private struct ReviewRow: Identifiable {
        let id = UUID()
        var name: String
        var notes: String
        var category: PartCategory
        var included: Bool
    }

    @State private var pastedText = ""
    @State private var fallbackCategory: PartCategory = .uncategorized
    @State private var rows: [ReviewRow] = []
    @State private var detectedInvestmentText: String?
    @State private var setDocumentedTotal = true
    @State private var keepFullSheetAsNote = true

    private var includedCount: Int {
        rows.filter(\.included).count
    }

    /// Pulls a plain number out of a detected money string like "$19,161.34".
    private var detectedInvestmentAmount: Double? {
        guard let text = detectedInvestmentText else { return nil }
        let cleaned = text.filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }

    var body: some View {
        NavigationStack {
            panesLayout
                .navigationTitle("Bulk Import Build Sheet")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(importTitle) { commitImport() }
                            .disabled(!canImport)
                    }
                }
        }
        .onChange(of: pastedText) { _, newValue in reparse(newValue) }
        .onChange(of: fallbackCategory) { _, _ in reparse(pastedText) }
        #if os(macOS)
        // Resizable and roomy — a build sheet is a lot of text to read while reviewing.
        .frame(minWidth: 720, idealWidth: 1100, maxWidth: .infinity,
               minHeight: 560, idealHeight: 820, maxHeight: .infinity)
        #endif
    }

    @ViewBuilder
    private var panesLayout: some View {
        #if os(macOS)
        HSplitView {
            editorPane.frame(minWidth: 340)
            previewPane.frame(minWidth: 400)
        }
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                editorPane
                Divider()
                previewPane
            }
        }
        #endif
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PASTE BUILD SHEET")
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1.5)
            Text("Paste the whole thing — section headers, \"Label: value\" lines, plain bullets, alignment specs, everything. Lines that look like specs or narrative (not physical parts) are pre-unchecked on the right instead of being dropped, so you can still opt them in.")
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
            TextEditor(text: $pastedText)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 420)
                .frame(maxHeight: .infinity)
                .border(HUDTheme.cyan.opacity(0.3))

            Toggle(isOn: $keepFullSheetAsNote) {
                Text("Keep the full pasted sheet as a note (nothing is lost)")
                    .font(HUDTheme.label())
            }
            .hudCheckboxStyle()

            if detectedInvestmentText != nil {
                Toggle(isOn: $setDocumentedTotal) {
                    Text("Set documented total investment — \(detectedInvestmentText ?? "")")
                        .font(HUDTheme.label())
                        .foregroundStyle(HUDTheme.green)
                }
                .hudCheckboxStyle()
            }

            Picker("Unknown lines →", selection: $fallbackCategory) {
                ForEach(PartCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            .font(HUDTheme.label())
        }
        .padding()
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PREVIEW — \(includedCount) OF \(rows.count) PARTS")
                    .font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .tracking(1.5)
                Spacer()
                if !rows.isEmpty {
                    Button("All") { setAllIncluded(true) }.buttonStyle(.plain).font(HUDTheme.label()).foregroundStyle(HUDTheme.cyan)
                    Button("None") { setAllIncluded(false) }.buttonStyle(.plain).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                }
            }

            if rows.isEmpty {
                Text("Nothing parsed yet — paste a build sheet on the left.")
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
                Spacer()
            } else {
                List {
                    ForEach($rows) { $row in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: $row.included)
                                .labelsHidden()
                                .hudCheckboxStyle()

                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name)
                                    .font(HUDTheme.body(.medium))
                                    .foregroundStyle(HUDTheme.textPrimary)
                                if !row.notes.isEmpty {
                                    Text(row.notes)
                                        .font(HUDTheme.label())
                                        .foregroundStyle(HUDTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                Picker("", selection: $row.category) {
                                    ForEach(PartCategory.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .labelsHidden()
                                .font(HUDTheme.label())
                                #if os(macOS)
                                .pickerStyle(.menu)
                                .frame(maxWidth: 180)
                                #endif
                            }
                        }
                        .opacity(row.included ? 1 : 0.4)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding()
    }

    private func reparse(_ text: String) {
        let result = BuildSheetParser.parse(text, fallbackCategory: fallbackCategory)
        rows = result.parts.map { parsed in
            ReviewRow(name: parsed.name, notes: parsed.notes, category: parsed.category, included: parsed.suggestedInclude)
        }
        detectedInvestmentText = result.detectedInvestmentText
    }

    private func setAllIncluded(_ included: Bool) {
        for index in rows.indices { rows[index].included = included }
    }

    private var hasSheetText: Bool {
        !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canImport: Bool {
        includedCount > 0
            || (keepFullSheetAsNote && hasSheetText)
            || (setDocumentedTotal && detectedInvestmentAmount != nil)
    }

    private var importTitle: String {
        includedCount > 0 ? "Import \(includedCount) Parts" : "Import"
    }

    private func commitImport() {
        for row in rows where row.included {
            vehicle.parts.append(Part(name: row.name, category: row.category, status: .installed, notes: row.notes))
        }
        // Route the money to the real field, not a loose note.
        if setDocumentedTotal, let amount = detectedInvestmentAmount {
            vehicle.documentedTotalInvestment = amount
        }
        // Preserve the full pasted sheet verbatim — never silently lose what the owner gave us.
        if keepFullSheetAsNote, hasSheetText {
            vehicle.notes.append(Note(title: "Imported build sheet", body: pastedText))
        }
        dismiss()
    }
}
