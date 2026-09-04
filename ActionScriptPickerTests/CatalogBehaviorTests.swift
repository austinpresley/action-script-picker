import XCTest

final class CatalogBehaviorTests: XCTestCase {
    func testParsesCompleteResponseInPanelOrder() throws {
        let catalog = try ActionCatalogParser.parse(#"{"sets":[{"name":"First","actions":[{"name":"One"},{"name":"Two"}]},{"name":"Second","actions":[]}]}"#)

        XCTAssertEqual(catalog.sets.map(\.name), ["First", "Second"])
        XCTAssertEqual(catalog.sets[0].actions.map(\.name), ["One", "Two"])
        XCTAssertEqual(catalog.sets[1].actions, [])
    }

    func testRejectsPartialOrMalformedResponse() {
        XCTAssertThrowsError(try ActionCatalogParser.parse(#"{"sets":[{"name":"Missing actions"}]}"#))
        XCTAssertThrowsError(try ActionCatalogParser.parse(#"{"sets":"not an array"}"#))
        XCTAssertThrowsError(try ActionCatalogParser.parse("{"))
    }

    func testPreservesExactSelectionAfterRefresh() throws {
        let old = try ActionCatalogParser.parse(#"{"sets":[{"name":"Web","actions":[{"name":"Small"},{"name":"Large"}]}]}"#)
        let new = try ActionCatalogParser.parse(#"{"sets":[{"name":"Print","actions":[{"name":"CMYK"}]},{"name":"Web","actions":[{"name":"Large"},{"name":"Small"}]}]}"#)

        let selection = SelectionResolver.selection(
            afterReplacing: old,
            oldSelection: ActionSelection(setID: 0, actionID: 1),
            with: new
        )

        XCTAssertEqual(selection, ActionSelection(setID: 1, actionID: 0))
    }

    func testFallsBackToFirstAvailableSelection() throws {
        let old = try ActionCatalogParser.parse(#"{"sets":[{"name":"Gone","actions":[{"name":"Old"}]}]}"#)
        let new = try ActionCatalogParser.parse(#"{"sets":[{"name":"New","actions":[]}]}"#)

        let selection = SelectionResolver.selection(
            afterReplacing: old,
            oldSelection: ActionSelection(setID: 0, actionID: 0),
            with: new
        )

        XCTAssertEqual(selection, ActionSelection(setID: 0, actionID: nil))
    }

    func testAmbiguityRules() throws {
        let catalog = try ActionCatalogParser.parse(#"{"sets":[{"name":"","actions":[{"name":"A"}]},{"name":"Same","actions":[{"name":"Duplicate"},{"name":"Duplicate"},{"name":""}]},{"name":"Same","actions":[{"name":"Valid elsewhere"}]}]}"#)

        XCTAssertNotNil(AmbiguityAnalyzer.ambiguity(for: catalog.sets[0].actions[0], in: catalog.sets[0], catalog: catalog))
        XCTAssertNotNil(AmbiguityAnalyzer.ambiguity(for: catalog.sets[1].actions[0], in: catalog.sets[1], catalog: catalog))
        XCTAssertNotNil(AmbiguityAnalyzer.ambiguity(for: catalog.sets[1].actions[2], in: catalog.sets[1], catalog: catalog))
        XCTAssertNotNil(AmbiguityAnalyzer.ambiguity(for: catalog.sets[2].actions[0], in: catalog.sets[2], catalog: catalog))
    }

    func testSameActionNameInDifferentUniqueSetsIsValid() throws {
        let catalog = try ActionCatalogParser.parse(#"{"sets":[{"name":"One","actions":[{"name":"Resize"}]},{"name":"Two","actions":[{"name":"Resize"}]}]}"#)

        XCTAssertNil(AmbiguityAnalyzer.ambiguity(for: catalog.sets[0].actions[0], in: catalog.sets[0], catalog: catalog))
        XCTAssertNil(AmbiguityAnalyzer.ambiguity(for: catalog.sets[1].actions[0], in: catalog.sets[1], catalog: catalog))
    }

    func testSearchIsCaseInsensitiveSubstringMatch() {
        let actions = [
            LoadedAction(id: 0, name: "Skin Clean"),
            LoadedAction(id: 1, name: "Resize for Web"),
            LoadedAction(id: 2, name: "SKIN Tone")
        ]

        XCTAssertEqual(ActionSearch.filter(actions, query: "skin").map(\.id), [0, 2])
        XCTAssertEqual(ActionSearch.filter(actions, query: "for").map(\.id), [1])
        XCTAssertEqual(ActionSearch.filter(actions, query: "").map(\.id), [0, 1, 2])
    }
}
