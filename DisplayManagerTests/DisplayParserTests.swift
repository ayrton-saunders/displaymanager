import XCTest

final class DisplayParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: DisplayParserTests.self)
        let url = bundle.url(
            forResource: name,
            withExtension: "txt",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: name, withExtension: "txt")
        guard let foundURL = url else {
            XCTFail("Missing fixture: \(name).txt — check Copy Bundle Resources")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: foundURL, encoding: .utf8)
    }

    func testParseDisplays_singleDisplay_returnsOneDisplayWithoutPlus() throws {
        XCTFail("intentional CI smoke-test failure — this PR exists only to prove the test gate rejects broken merges. Do NOT merge.")
        let output = try fixture("single-display")
        let displays = DisplayParser.parseDisplays(output)
        XCTAssertEqual(displays.count, 1)
        XCTAssertFalse(displays[0].id.contains("+"))
        XCTAssertTrue(displays[0].config.contains("id:\(displays[0].id)"))
    }

    func testParseDisplays_extendedMode_returnsTwoDisplaysNoPlus() throws {
        let output = try fixture("extended-builtin-plus-dell")
        let displays = DisplayParser.parseDisplays(output)
        XCTAssertEqual(displays.count, 2)
        XCTAssertFalse(displays[0].id.contains("+"))
        XCTAssertFalse(displays[1].id.contains("+"))
        XCTAssertTrue(
            displays.contains(where: { $0.config.contains("origin:(0,0)") }),
            "Expected one display anchored at origin:(0,0) (the built-in)"
        )
    }

    func testParseDisplays_mirroredMode_returnsOneDisplayWithPlus() throws {
        let output = try fixture("mirrored-two-displays")
        let displays = DisplayParser.parseDisplays(output)
        XCTAssertEqual(displays.count, 1)
        XCTAssertTrue(displays[0].id.contains("+"))
    }

    func testParseDisplays_garbageInput_returnsEmptyArrayWithoutCrash() {
        XCTAssertEqual(DisplayParser.parseDisplays(""), [])
        XCTAssertEqual(DisplayParser.parseDisplays("nonsense"), [])
        XCTAssertEqual(DisplayParser.parseDisplays("displayplacer"), [])
        XCTAssertEqual(
            DisplayParser.parseDisplays("displayplacer \"missing close quote"),
            []
        )
    }

    func testDetectMode_emptyInput_isUnknown() {
        XCTAssertEqual(DisplayParser.detectMode([]), .unknown)
    }

    func testDetectMode_singleDisplay_isUnknown() throws {
        let displays = DisplayParser.parseDisplays(try fixture("single-display"))
        XCTAssertEqual(DisplayParser.detectMode(displays), .unknown)
    }

    func testDetectMode_extendedFixture_isExtended() throws {
        let displays = DisplayParser.parseDisplays(try fixture("extended-builtin-plus-dell"))
        XCTAssertEqual(DisplayParser.detectMode(displays), .extended)
    }

    func testDetectMode_mirroredFixture_isMirrored() throws {
        let displays = DisplayParser.parseDisplays(try fixture("mirrored-two-displays"))
        XCTAssertEqual(DisplayParser.detectMode(displays), .mirrored)
    }
}
