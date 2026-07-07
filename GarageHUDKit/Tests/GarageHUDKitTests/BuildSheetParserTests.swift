import XCTest
@testable import GarageHUDKit

/// TD-002: the build-sheet parser is complex and user-facing (a bad parse silently
/// produces junk parts), so it earns direct coverage.
final class BuildSheetParserTests: XCTestCase {
    func testCategorizesCommonPartsByKeyword() {
        let sheet = """
        ENGINE
        • Turbo: BorgWarner EFR
        • Injectors: ID1300
        EXHAUST
        • Downpipe: Invidia
        """
        let result = BuildSheetParser.parse(sheet, fallbackCategory: .uncategorized)
        func category(of name: String) -> PartCategory? {
            result.parts.first { $0.name == name }?.category
        }
        XCTAssertEqual(category(of: "Turbo"), .forcedInduction)
        XCTAssertEqual(category(of: "Injectors"), .fueling)
        XCTAssertEqual(category(of: "Downpipe"), .exhaust)
    }

    func testDetectsInvestmentTotalWithoutMakingItAPart() {
        let result = BuildSheetParser.parse("• Total Invested: $19,161.34", fallbackCategory: .uncategorized)
        XCTAssertEqual(result.detectedInvestmentText, "$19,161.34")
        XCTAssertFalse(result.parts.contains { $0.name.localizedCaseInsensitiveContains("total") })
    }

    func testUnrecognizedPartFallsToUncategorizedNotAWrongBucket() {
        let result = BuildSheetParser.parse("• Vinyl decal", fallbackCategory: .uncategorized)
        XCTAssertEqual(result.parts.count, 1)
        XCTAssertEqual(result.parts.first?.category, .uncategorized)
    }

    func testNarrativeUnderNonPartSectionIsSuggestedExcluded() {
        let sheet = """
        Performance
        • 477 WHP / 317 WTQ on E85
        """
        let result = BuildSheetParser.parse(sheet, fallbackCategory: .uncategorized)
        XCTAssertEqual(result.parts.count, 1)
        // Lines under a "Performance" section read as spec/narrative, not a purchasable part.
        XCTAssertFalse(result.parts.first?.suggestedInclude ?? true)
    }

    func testRealPartUnderPartSectionIsSuggestedIncluded() {
        let sheet = """
        Suspension
        • Coilovers: Ohlins Road & Track
        """
        let result = BuildSheetParser.parse(sheet, fallbackCategory: .uncategorized)
        XCTAssertEqual(result.parts.first?.suggestedInclude, true)
        XCTAssertEqual(result.parts.first?.category, .suspension)
    }
}
