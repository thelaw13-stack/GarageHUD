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
    @State private var fallbackCategory: PartCategory = .engine
    @State private var rows: [ReviewRow] = []
    @State private var detectedInvestmentText: String?
    @State private var includeInvestmentNote = true

    private var includedCount: Int {
        rows.filter(\.included).count
    }

    var body: some View {
        NavigationStack {
            panesLayout
                .navigationTitle("Bulk Import Build Sheet")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(includedCount) Parts") { commitImport() }
                            .disabled(includedCount == 0)
                    }
                }
        }
        .onChange(of: pastedText) { _, newValue in reparse(newValue) }
        .onChange(of: fallbackCategory) { _, _ in reparse(pastedText) }
        .frame(minWidth: 820, minHeight: 580)
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
                .font(HUDTheme.monoFont(11, weight: .semibold))
                .foregroundStyle(HUDTheme.cyan)
                .tracking(1.5)
            Text("Paste the whole thing — section headers, \"Label: value\" lines, plain bullets, alignment specs, everything. Lines that look like specs or narrative (not physical parts) are pre-unchecked on the right instead of being dropped, so you can still opt them in.")
                .font(HUDTheme.monoFont(10))
                .foregroundStyle(HUDTheme.textSecondary)
            TextEditor(text: $pastedText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 320)
                .border(HUDTheme.cyan.opacity(0.3))
            Picker("Fallback category", selection: $fallbackCategory) {
                ForEach(PartCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("Used when a line's category can't be guessed at all.")
                .font(HUDTheme.monoFont(9))
                .foregroundStyle(HUDTheme.textSecondary)
        }
        .padding()
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PREVIEW — \(includedCount) OF \(rows.count) PARTS")
                    .font(HUDTheme.monoFont(11, weight: .semibold))
                    .foregroundStyle(HUDTheme.cyan)
                    .tracking(1.5)
                Spacer()
                if !rows.isEmpty {
                    Button("All") { setAllIncluded(true) }.buttonStyle(.plain).font(HUDTheme.monoFont(10)).foregroundStyle(HUDTheme.cyan)
                    Button("None") { setAllIncluded(false) }.buttonStyle(.plain).font(HUDTheme.monoFont(10)).foregroundStyle(HUDTheme.textSecondary)
                }
            }

            if let investment = detectedInvestmentText {
                Toggle(isOn: $includeInvestmentNote) {
                    Text("Add note: Total Investment — \(investment)")
                        .font(HUDTheme.monoFont(11))
                }
                .hudCheckboxStyle()
            }

            if rows.isEmpty {
                Text("Nothing parsed yet — paste a build sheet on the left.")
                    .font(HUDTheme.monoFont(11))
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
                                    .font(HUDTheme.monoFont(12, weight: .medium))
                                    .foregroundStyle(HUDTheme.textPrimary)
                                if !row.notes.isEmpty {
                                    Text(row.notes)
                                        .font(HUDTheme.monoFont(10))
                                        .foregroundStyle(HUDTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                Picker("", selection: $row.category) {
                                    ForEach(PartCategory.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .labelsHidden()
                                .font(HUDTheme.monoFont(9))
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

    private func commitImport() {
        for row in rows where row.included {
            let part = Part(name: row.name, category: row.category, status: .installed, notes: row.notes)
            vehicle.parts.append(part)
        }
        if includeInvestmentNote, let investment = detectedInvestmentText {
            vehicle.notes.append(Note(title: "Total Investment", body: investment))
        }
        dismiss()
    }
}
