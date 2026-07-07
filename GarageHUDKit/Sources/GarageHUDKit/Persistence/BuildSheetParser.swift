import Foundation

/// Turns a pasted, bullet-style build sheet (the kind people already keep in notes
/// apps or forum posts) into `Part` entries, so a whole build doesn't have to be
/// typed into the Add Part form one item at a time.
enum BuildSheetParser {
    struct ParsedPart {
        var name: String
        var notes: String
        var category: PartCategory
        /// False for lines that look like specs/narrative/checklists rather than a
        /// physical part (long sentences, alignment numbers, "✔" checklist items,
        /// or anything under a section header like "Performance" or "Philosophy").
        /// Callers should default these to unchecked in a review UI, not silently drop them.
        var suggestedInclude: Bool
    }

    struct ParseResult {
        var parts: [ParsedPart]
        var detectedInvestmentText: String?
    }

    private static let nonPartSectionKeywords = [
        "performance", "rebuild", "baseline", "philosophy", "investment",
        "alignment", "data system", "current", "locked"
    ]

    static func parse(_ text: String, fallbackCategory: PartCategory) -> ParseResult {
        var currentSectionCategory = fallbackCategory
        var currentSectionName = ""
        var currentGroupCategory: PartCategory?
        var parts: [ParsedPart] = []
        var investmentText: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let bulletChars = CharacterSet(charactersIn: "•-*\u{2022}\t ")
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let isBullet = line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*")
            let cleaned = line.trimmingCharacters(in: bulletChars)
            guard !cleaned.isEmpty else { continue }

            if !isBullet {
                currentSectionCategory = categoryHint(for: cleaned) ?? fallbackCategory
                currentSectionName = cleaned.lowercased()
                currentGroupCategory = nil
                continue
            }

            let (label, value) = splitLabelValue(cleaned)
            let sectionLooksNonPart = nonPartSectionKeywords.contains { currentSectionName.contains($0) }

            guard let value else {
                if cleaned.hasSuffix(":") {
                    currentGroupCategory = categoryHint(for: label)
                    continue
                }
                if isInvestmentLine(label) {
                    investmentText = label
                    continue
                }
                let category = categoryHint(for: label) ?? currentGroupCategory ?? currentSectionCategory
                parts.append(ParsedPart(
                    name: label,
                    notes: "",
                    category: category,
                    suggestedInclude: !sectionLooksNonPart && !looksLikeNonPartLine(label)
                ))
                continue
            }

            if isInvestmentLine(label) {
                investmentText = value
                continue
            }

            let category = categoryHint(for: label) ?? categoryHint(for: value) ?? currentGroupCategory ?? currentSectionCategory
            parts.append(ParsedPart(
                name: label,
                notes: value,
                category: category,
                suggestedInclude: !sectionLooksNonPart && !looksLikeNonPartLine(value)
            ))
        }

        return ParseResult(parts: parts, detectedInvestmentText: investmentText)
    }

    private static func splitLabelValue(_ line: String) -> (label: String, value: String?) {
        guard let colonIndex = line.firstIndex(of: ":") else { return (line, nil) }
        let label = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let rest = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        return (label, rest.isEmpty ? nil : rest)
    }

    private static func isInvestmentLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("total") && (lower.contains("invest") || lower.contains("cost"))
    }

    /// Long sentences, checklist marks, and angle/measurement specs read as narrative
    /// or setup data, not a purchasable part.
    private static func looksLikeNonPartLine(_ text: String) -> Bool {
        if text.hasPrefix("✔") || text.hasPrefix("✓") { return true }
        if text.contains("°") { return true }
        if text.count > 70 { return true }
        return false
    }

    private static let categoryTable: [(keywords: [String], category: PartCategory)] = [
        (["turbo", "supercharger", "intercooler", "boost", "wastegate", "blow off"], .forcedInduction),
        (["injector", "fuel pump", "fuel system", "e85", "fuel regulator", "fuel"], .fueling),
        (["header", "downpipe", "exhaust", "muffler", "catback", "cat-back"], .exhaust),
        (["radiator", "oil cooler", "cooling", "air/oil separator"], .cooling),
        (["brake", "caliper", "rotor", "brembo", "bbk"], .brakes),
        (["coilover", "coil-over", "sway bar", "bushing", "suspension", "strut", "roll center", "bump steer", "ball joint", "chassis brace", "tower brace"], .suspension),
        (["wheel", "tire", "rim", "lug nut"], .wheelsAndTires),
        (["paint", "fender", "wiper", "body kit", "bumper"], .exterior),
        (["stereo", "speaker", "subwoofer", "gauge", "tune", "tuning", "ecu", "data logger", "dash"], .electronics),
        (["seat", "interior", "steering wheel", "shift knob"], .interior),
        (["head stud", "engine", "motor", "intake", "oil pickup", "piston", "rod", "block", "ignition", "coil", "spark plug"], .engine),
        (["clutch", "transmission", "differential", "driveshaft", "axle"], .drivetrain)
    ]

    /// Also used by the Parts quick-add bar so single entries get the same keyword
    /// auto-categorization as pasted build sheets.
    static func categoryHint(for text: String) -> PartCategory? {
        let lower = text.lowercased()
        for entry in categoryTable where entry.keywords.contains(where: { lower.contains($0) }) {
            return entry.category
        }
        return nil
    }
}
