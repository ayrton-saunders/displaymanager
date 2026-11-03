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

    // MARK: - extendedConfigArguments (capture for persistence)

    func testExtendedConfigArguments_extendedFixture_returnsBothConfigsVerbatim() throws {
        let args = DisplayParser.extendedConfigArguments(try fixture("extended-builtin-plus-dell"))
        XCTAssertEqual(args?.count, 2)
        // The real external arrangement must be preserved exactly — this is the
        // arrangement that was being clobbered by the hardcoded fallback.
        XCTAssertTrue(
            args?.contains(where: { $0.contains("origin:(-423,-1440)") && $0.contains("res:2560x1440") }) ?? false,
            "External display config must preserve its real origin (-423,-1440) and resolution"
        )
        XCTAssertTrue(
            args?.contains(where: { $0.contains("origin:(0,0)") }) ?? false,
            "Built-in display config must be captured"
        )
    }

    func testExtendedConfigArguments_mirroredFixture_returnsNil() throws {
        // A mirrored snapshot does not contain the real extended layout, so there
        // is nothing safe to capture — must not fabricate one.
        XCTAssertNil(DisplayParser.extendedConfigArguments(try fixture("mirrored-two-displays")))
    }

    func testExtendedConfigArguments_singleDisplay_returnsNil() throws {
        XCTAssertNil(DisplayParser.extendedConfigArguments(try fixture("single-display")))
    }

    func testExtendedConfigArguments_garbageInput_returnsNil() {
        XCTAssertNil(DisplayParser.extendedConfigArguments(""))
        XCTAssertNil(DisplayParser.extendedConfigArguments("nonsense"))
    }

    // MARK: - laptop-optimized mirroring

    private var expectedLaptopMirror: String {
        "id:\(builtInID)+\(dellID) res:1728x1117 hz:120 color_depth:8 scaling:on enabled:true origin:(0,0) degree:0"
    }

    func testMirrorConfig_dellPrimary_usesHardwareRoleAndLaptopScaling() throws {
        let output = try fixture("extended-dell-primary")
        XCTAssertEqual(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: []), expectedLaptopMirror)
    }

    func testMirrorConfig_builtinPrimary_preservesExistingBehavior() throws {
        let output = try fixture("extended-builtin-plus-dell")
        XCTAssertEqual(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: []), expectedLaptopMirror)
    }

    func testMirrorConfig_doesNotHardcodeLaptopResolutionOrScaling() throws {
        let output = try fixture("extended-dell-primary")
            .replacingOccurrences(of: "res:1728x1117", with: "res:1496x967")
            .replacingOccurrences(of: "scaling:on", with: "scaling:off")
        let expected = expectedLaptopMirror
            .replacingOccurrences(of: "res:1728x1117", with: "res:1496x967")
            .replacingOccurrences(of: "scaling:on", with: "scaling:off")
        XCTAssertEqual(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: []), expected)
    }

    func testMirrorConfig_dellSourceMirror_usesSavedLaptopGeometryNotCurrentMirror() throws {
        let saved = try XCTUnwrap(DisplayParser.extendedConfigArguments(try fixture("extended-dell-primary")))
        let output = try fixture("mirrored-dell-source")
        XCTAssertEqual(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: saved), expectedLaptopMirror)
    }

    func testMirrorConfig_repeatedMirror_usesSavedLaptopGeometry() throws {
        let saved = try XCTUnwrap(DisplayParser.extendedConfigArguments(try fixture("extended-dell-primary")))
        let output = try fixture("mirrored-two-displays")
        XCTAssertEqual(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: saved), expectedLaptopMirror)
    }

    func testMirrorConfig_mirroredWithoutSnapshot_doesNotGuessLaptopGeometry() throws {
        XCTAssertNil(DisplayParser.mirrorConfigArgument(try fixture("mirrored-dell-source"), savedExtendedConfig: []))
    }

    func testMirrorConfig_staleOrInvalidSnapshot_doesNotReuseIt() throws {
        let saved = try XCTUnwrap(DisplayParser.extendedConfigArguments(try fixture("extended-dell-primary")))
        let output = try fixture("mirrored-dell-source")
        let stale = saved.map { $0.replacingOccurrences(of: dellID, with: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") }
        XCTAssertNil(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: stale))
        XCTAssertNil(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: [saved[0]]))
        XCTAssertNil(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: saved + ["garbage"]))
    }

    func testMirrorConfig_freshHardwareIDsAndChangedContextualIDs_areDiscoveredByRole() throws {
        let output = try fixture("extended-dell-primary")
            .replacingOccurrences(of: builtInID, with: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
            .replacingOccurrences(of: dellID, with: "11111111-2222-3333-4444-555555555555")
        let expected = expectedLaptopMirror
            .replacingOccurrences(of: builtInID, with: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
            .replacingOccurrences(of: dellID, with: "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(DisplayParser.mirrorConfigArgument(output, savedExtendedConfig: []), expected)
    }

    func testMirrorConfig_missingOrAmbiguousHardwareRole_doesNotGuessFromOrigin() throws {
        let output = try fixture("extended-dell-primary")
        for type in ["unknown screen", "27 inch external screen"] {
            let missingRole = output.replacingOccurrences(of: "MacBook built in screen", with: type)
            XCTAssertNil(DisplayParser.mirrorConfigArgument(missingRole, savedExtendedConfig: []))
        }
        let ambiguous = output.replacingOccurrences(of: "27 inch external screen", with: "MacBook built in screen")
        XCTAssertNil(DisplayParser.mirrorConfigArgument(ambiguous, savedExtendedConfig: []))
    }

    func testMirrorConfig_missingLaptopScalingOrDisabledLaptop_doesNotGuess() throws {
        let output = try fixture("extended-dell-primary")
        XCTAssertNil(DisplayParser.mirrorConfigArgument(
            output.replacingOccurrences(of: "scaling:on", with: ""), savedExtendedConfig: []
        ))
        XCTAssertNil(DisplayParser.mirrorConfigArgument(
            output.replacingOccurrences(of: "enabled:true", with: "enabled:false"), savedExtendedConfig: []
        ))
    }

    func testMirrorConfig_unsupportedArrangements_returnNil() throws {
        XCTAssertNil(DisplayParser.mirrorConfigArgument(try fixture("single-display"), savedExtendedConfig: []))
        let threeDisplays = try fixture("extended-dell-primary").trimmingCharacters(in: .whitespacesAndNewlines)
            + " \"id:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE res:1920x1080 scaling:on origin:(-1920,0) degree:0\""
        XCTAssertNil(DisplayParser.mirrorConfigArgument(threeDisplays, savedExtendedConfig: []))
        XCTAssertNil(DisplayParser.mirrorConfigArgument("nonsense", savedExtendedConfig: []))
    }

    func testExtendedConfigArguments_dellPrimary_roundTripPreservesExactDeskArrangement() throws {
        let output = try fixture("extended-dell-primary")
        let expected = DisplayParser.parseDisplays(output).map { $0.config }
        let saved = try XCTUnwrap(DisplayParser.extendedConfigArguments(output))
        XCTAssertEqual(saved, expected)
        XCTAssertTrue(saved[0].contains("id:\(dellID) res:2560x1440"))
        XCTAssertTrue(saved[0].contains("origin:(0,0)"))
        XCTAssertTrue(saved[1].contains("origin:(423,1440)"))
        let mirrored = try fixture("mirrored-dell-source")
        XCTAssertNil(DisplayParser.extendedConfigArguments(mirrored), "Mirroring must not overwrite the desk snapshot")
        XCTAssertTrue(DisplayParser.savedConfigIsRestorable(saved, against: mirrored))
        XCTAssertEqual(DisplayParser.mirrorConfigArgument(mirrored, savedExtendedConfig: saved), expectedLaptopMirror)
        XCTAssertEqual(saved, expected, "Mirror planning must not modify the saved primary, positions or scaling")
    }

    // MARK: - connectedDisplayIDs

    private let builtInID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    private let dellID = "5D33ABED-7F2F-45F6-BECD-EDD7869FBD0B"

    func testConnectedDisplayIDs_extended_returnsBothHardwareIDs() throws {
        let ids = DisplayParser.connectedDisplayIDs(try fixture("extended-builtin-plus-dell"))
        XCTAssertEqual(ids, [builtInID, dellID])
    }

    func testConnectedDisplayIDs_mirrored_expandsCombinedID() throws {
        // A mirrored snapshot reports one "A+B" id — both hardware IDs must be recovered.
        let ids = DisplayParser.connectedDisplayIDs(try fixture("mirrored-two-displays"))
        XCTAssertEqual(ids, [builtInID, dellID])
    }

    func testConnectedDisplayIDs_singleDisplay_returnsOne() throws {
        let ids = DisplayParser.connectedDisplayIDs(try fixture("single-display"))
        XCTAssertEqual(ids.count, 1)
    }

    func testConnectedDisplayIDs_garbage_returnsEmpty() {
        XCTAssertTrue(DisplayParser.connectedDisplayIDs("nonsense").isEmpty)
    }

    // MARK: - savedConfigIsRestorable (stale-config guard)

    func testSavedConfigIsRestorable_sameDisplaysConnected_isTrue() throws {
        let saved = try XCTUnwrap(DisplayParser.extendedConfigArguments(try fixture("extended-builtin-plus-dell")))
        // The same two monitors are present, now mirrored — restoring is safe.
        XCTAssertTrue(DisplayParser.savedConfigIsRestorable(saved, against: try fixture("mirrored-two-displays")))
    }

    func testSavedConfigIsRestorable_externalDisconnected_isFalse() throws {
        let saved = try XCTUnwrap(DisplayParser.extendedConfigArguments(try fixture("extended-builtin-plus-dell")))
        // Only the built-in remains — the saved external is gone, so replaying its
        // stale ID would fail. Must not attempt it.
        XCTAssertFalse(DisplayParser.savedConfigIsRestorable(saved, against: try fixture("single-display")))
    }

    func testSavedConfigIsRestorable_emptySaved_isFalse() throws {
        XCTAssertFalse(DisplayParser.savedConfigIsRestorable([], against: try fixture("extended-builtin-plus-dell")))
    }
}
