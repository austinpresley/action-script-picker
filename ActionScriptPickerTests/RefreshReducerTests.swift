import XCTest

final class RefreshReducerTests: XCTestCase {
    func testSuccessReplacesCatalogAtomicallyAndPreservesSameTargetSelection() throws {
        let first = try ActionCatalogParser.parse(#"{"sets":[{"name":"Set","actions":[{"name":"A"},{"name":"B"}]}]}"#)
        let replacement = try ActionCatalogParser.parse(#"{"sets":[{"name":"Set","actions":[{"name":"B"}]}]}"#)
        let previous = RefreshSnapshot(
            catalog: first,
            dataTargetID: "/Photoshop.app",
            isStale: false,
            selection: ActionSelection(setID: 0, actionID: 1)
        )

        let result = RefreshReducer.success(previous: previous, targetID: "/Photoshop.app", catalog: replacement)

        XCTAssertEqual(result.catalog, replacement)
        XCTAssertEqual(result.selection, ActionSelection(setID: 0, actionID: 0))
        XCTAssertFalse(result.isStale)
    }

    func testSameTargetFailureRetainsResultsAsStale() throws {
        let catalog = try ActionCatalogParser.parse(#"{"sets":[{"name":"Set","actions":[{"name":"A"}]}]}"#)
        let previous = RefreshSnapshot(
            catalog: catalog,
            dataTargetID: "same",
            isStale: false,
            selection: ActionSelection(setID: 0, actionID: 0)
        )

        let result = RefreshReducer.failure(previous: previous, targetID: "same")

        XCTAssertEqual(result.catalog, catalog)
        XCTAssertTrue(result.isStale)
    }

    func testDifferentTargetFailureClearsOldResults() throws {
        let catalog = try ActionCatalogParser.parse(#"{"sets":[{"name":"Set","actions":[{"name":"A"}]}]}"#)
        let previous = RefreshSnapshot(
            catalog: catalog,
            dataTargetID: "old",
            isStale: false,
            selection: ActionSelection(setID: 0, actionID: 0)
        )

        XCTAssertEqual(RefreshReducer.failure(previous: previous, targetID: "new"), .empty)
    }
}
