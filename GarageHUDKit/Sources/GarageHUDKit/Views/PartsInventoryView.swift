import SwiftUI

struct PartsInventoryView: View {
    @EnvironmentObject private var store: GarageStore
    @Binding var vehicle: Vehicle
    @State private var showingAddPart = false
    @State private var showingBulkImport = false
    @State private var editingPart: Part?
    @State private var filterStatus: PartStatus?
    @State private var searchText = ""
    @State private var quickAddName = ""

    private var filteredParts: [Part] {
        var items = vehicle.parts
        if let filterStatus {
            items = items.filter { $0.status == filterStatus }
        }
        if !searchText.isEmpty {
            let needle = searchText.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(needle)
                    || $0.brand.lowercased().contains(needle)
                    || $0.notes.lowercased().contains(needle)
                    || $0.partNumber.lowercased().contains(needle)
            }
        }
        return items
    }

    private var groupedParts: [(PartCategory, [Part])] {
        let grouped = Dictionary(grouping: filteredParts, by: \.category)
        return PartCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            summaryStrip
            quickAddBar
            if groupedParts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedParts, id: \.0) { category, parts in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(category.rawValue.uppercased()) (\(parts.count))")
                                    .font(HUDTheme.label(.semibold))
                                    .foregroundStyle(HUDTheme.amber)
                                    .tracking(1.5)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                                    ForEach(parts) { part in
                                        PartCard(part: part)
                                            .contentShape(Rectangle())
                                            .onTapGesture { editingPart = part }
                                            .contextMenu {
                                                let others = store.vehicles.filter { $0.id != vehicle.id }
                                                if !others.isEmpty {
                                                    Menu("Move to…") {
                                                        ForEach(others) { dest in
                                                            Button(dest.displayName) {
                                                                store.moveParts(partID: part.id, from: vehicle.id, to: dest.id)
                                                            }
                                                        }
                                                    }
                                                }
                                                Button("Delete", role: .destructive) {
                                                    vehicle.parts.removeAll { $0.id == part.id }
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(HUDTheme.background)
        .sheet(isPresented: $showingAddPart) {
            AddEditPartView(vehicle: $vehicle, partID: nil)
        }
        .sheet(item: $editingPart) { part in
            AddEditPartView(vehicle: $vehicle, partID: part.id)
        }
        .sheet(isPresented: $showingBulkImport) {
            BulkImportPartsView(vehicle: $vehicle)
        }
    }

    // Stacks vertically so it fits a phone's width instead of crushing the search,
    // filter, and paste controls into one cramped row.
    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HUDTheme.textSecondary)
                TextField("Search parts by name, brand, or notes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(HUDTheme.body())
            }
            .padding(8)
            .background(HUDTheme.panelBackground)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.cyan.opacity(0.3), lineWidth: 1))

            HStack(spacing: 10) {
                // Menu picker instead of segmented — segmented truncates status labels on a phone.
                Menu {
                    Picker("Filter", selection: $filterStatus) {
                        Text("All").tag(PartStatus?.none)
                        ForEach(PartStatus.allCases) { status in
                            Text(status.rawValue).tag(PartStatus?.some(status))
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filterStatus?.rawValue ?? "All Parts")
                            .font(HUDTheme.label(.medium))
                    }
                    .foregroundStyle(HUDTheme.cyan)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.cyan.opacity(0.4), lineWidth: 1))
                }
                Spacer()
                Button {
                    showingBulkImport = true
                } label: {
                    Label("Paste Build Sheet", systemImage: "doc.text.below.ecg")
                }
                .buttonStyle(.attentionAction)
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
    }

    // Horizontal scroll keeps each stat on one line ("$0.00" was wrapping to two rows on a phone).
    private var summaryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                summaryItem(vehicle.totalInvested.formatted(.currency(code: "USD")), "TOTAL INVESTED", color: HUDTheme.green, big: true)
                summaryItem("\(vehicle.parts.count)", "TOTAL PARTS")
                summaryItem("\(vehicle.installedPartsCount)", "INSTALLED")
                summaryItem("\(vehicle.wishlistPartsCount)", "WISHLIST")
                if !searchText.isEmpty || filterStatus != nil {
                    summaryItem("\(filteredParts.count)", "SHOWN", color: HUDTheme.textSecondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 10)
    }

    private func summaryItem(_ value: String, _ label: String, color: Color = HUDTheme.cyan, big: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(HUDTheme.monoFont(big ? 18 : 13, weight: .bold))
                .foregroundStyle(color)
                .fixedSize()
            Text(label)
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1)
                .fixedSize()
        }
    }

    private var quickAddBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundStyle(HUDTheme.cyan)
            TextField("Quick add a part by name, press Return...", text: $quickAddName)
                .textFieldStyle(.plain)
                .font(HUDTheme.body())
                .onSubmit(quickAdd)
            if !quickAddName.isEmpty {
                Text("→ \(detectedQuickAddCategory.rawValue)")
                    .font(HUDTheme.label())
                    .foregroundStyle(detectedQuickAddCategory == .uncategorized ? HUDTheme.textSecondary : HUDTheme.amber)
            }
            Button("Add", action: quickAdd)
                .buttonStyle(.primaryAction)
                .disabled(quickAddName.isEmpty)
            Divider().frame(height: 16)
            Button {
                showingAddPart = true
            } label: {
                Label("Full Form", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.plain)
            .font(HUDTheme.label())
            .foregroundStyle(HUDTheme.textSecondary)
        }
        .padding(8)
        .background(HUDTheme.panelBackground)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.cyan.opacity(0.2), lineWidth: 1))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    /// Same keyword auto-categorization as bulk paste; anything unguessable lands
    /// visibly in Uncategorized rather than silently in a wrong bucket.
    private var detectedQuickAddCategory: PartCategory {
        BuildSheetParser.categoryHint(for: quickAddName) ?? .uncategorized
    }

    private func quickAdd() {
        guard !quickAddName.isEmpty else { return }
        vehicle.parts.append(Part(name: quickAddName, category: detectedQuickAddCategory, status: .installed))
        quickAddName = ""
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 32))
                .foregroundStyle(HUDTheme.textSecondary)
            Text(searchText.isEmpty ? "No parts logged yet" : "No parts match \"\(searchText)\"")
                .font(HUDTheme.body())
                .foregroundStyle(HUDTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PartCard: View {
    var part: Part

    private var statusColor: Color {
        switch part.status {
        case .installed: HUDTheme.green
        case .wishlist: HUDTheme.amber
        case .removed: HUDTheme.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(part.name)
                        .font(HUDTheme.body(.bold))
                        .foregroundStyle(HUDTheme.textPrimary)
                    if !part.brand.isEmpty || !part.partNumber.isEmpty {
                        Text([part.brand, part.partNumber].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.cyan)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let cost = part.cost {
                        Text(cost.formatted(.currency(code: "USD")))
                            .font(HUDTheme.section(.bold))
                            .foregroundStyle(HUDTheme.green)
                    } else {
                        Text("no cost")
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.textSecondary.opacity(0.6))
                    }
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(part.status.rawValue.uppercased())
                            .font(HUDTheme.label(.medium))
                            .foregroundStyle(HUDTheme.textSecondary)
                    }
                }
            }

            if !part.notes.isEmpty {
                Text(part.notes)
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(statusColor.opacity(0.25), lineWidth: 1))
    }
}
