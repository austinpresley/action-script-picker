import XCTest

final class PhotoshopQuerySourceTests: XCTestCase {
    func testQueryUsesInlineCompatibilitySerializerAndActionManagerOrder() {
        let source = PhotoshopActionQuery.javaScriptSource

        XCTAssertTrue(source.contains("function stringifyJSON"))
        XCTAssertFalse(source.contains("JSON.stringify"))
        XCTAssertTrue(source.contains("putIndex(typeID('ASet'), setIndex)"))
        XCTAssertTrue(source.contains("putIndex(typeID('Actn'), actionIndex)"))
    }
}
