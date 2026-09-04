import Foundation
import XCTest

final class AppleScriptGeneratorTests: XCTestCase {
    func testGeneratesExactBundleIdentifierScript() {
        let source = AppleScriptGenerator.generate(
            actionName: "AI SKIN CLEAN",
            setName: "BUILDING STATION",
            target: .bundleIdentifier("com.adobe.Photoshop")
        )

        XCTAssertEqual(source, """
        tell application id "com.adobe.Photoshop"
            activate
            do action "AI SKIN CLEAN" from "BUILDING STATION"
        end tell

        """)
        XCTAssertTrue(source.hasSuffix("\n"))
        XCTAssertFalse(source.hasSuffix("\n\n"))
    }

    func testGeneratesExactPathTargetedScript() {
        let source = AppleScriptGenerator.generate(
            actionName: "Resize",
            setName: "Web",
            target: .applicationPath("/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app")
        )

        XCTAssertTrue(source.hasPrefix("tell application \"/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app\"\n"))
    }

    func testEscapesQuotesAndBackslashes() {
        XCTAssertEqual(
            AppleScriptString.expression(for: "A \\\"quoted\\\" \\\\ name"),
            "\"A \\\\\\\"quoted\\\\\\\" \\\\\\\\ name\""
        )
    }

    func testEncodesTabsAndLineBreaksAsStringExpression() {
        XCTAssertEqual(
            AppleScriptString.expression(for: "one\ttwo\nthree\rfour"),
            "(\"one\" & character id 9 & \"two\" & character id 10 & \"three\" & character id 13 & \"four\")"
        )
    }

    func testRetainsNonLatinTextAndEmoji() {
        XCTAssertEqual(AppleScriptString.expression(for: "肌補正 ✨"), "\"肌補正 ✨\"")
    }

    func testSpecialCharacterExpressionsRoundTripThroughAppleScript() throws {
        let values = [
            "A \\\"quoted\\\" \\\\ name",
            "one\ttwo\nthree\rfour",
            "肌補正 ✨"
        ]

        for value in values {
            let source = "return \(AppleScriptString.expression(for: value))"
            let script = try XCTUnwrap(NSAppleScript(source: source))
            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            XCTAssertNil(errorInfo, "AppleScript failed for \(source): \(String(describing: errorInfo))")
            XCTAssertEqual(result.stringValue, value)
        }
    }
}
