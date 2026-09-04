import AppKit
import SwiftUI
import XCTest

@MainActor
final class ContentViewLayoutTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.close() }
        windows.removeAll()
        super.tearDown()
    }

    func testLongActionListKeepsSearchVisibleAndPreviewExpanded() throws {
        let model = AppModel(uiFixture: try fixtureCatalog())
        let (window, host) = host(model)

        let searches = descendants(of: host, matching: NSTextField.self)
            .filter { $0.placeholderString == "Search actions" }
        XCTAssertFalse(searches.isEmpty)
        let preview = try XCTUnwrap(
            descendants(of: host, matching: NSTextView.self)
                .first(where: { $0.string.contains("tell application") })
        )

        XCTAssertGreaterThan(preview.enclosingScrollView?.frame.height ?? 0, 200)
        XCTAssertGreaterThan(preview.frame.height, 40, "Preview document view collapsed to \(preview.frame)")
        var foreground: NSColor?
        var background: NSColor?
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            foreground = preview.textColor?.usingColorSpace(.deviceRGB)
            background = NSColor.textBackgroundColor.usingColorSpace(.deviceRGB)
        }
        XCTAssertGreaterThan(
            colorDistance(foreground, background),
            0.35,
            "Preview foreground \(String(describing: foreground)) blends into \(String(describing: background))"
        )
        let searchFrames = searches.map { $0.convert($0.bounds, to: nil) }
        XCTAssertTrue(
            searchFrames.contains(where: window.contentLayoutRect.contains),
            "Search frames \(searchFrames) are outside content layout \(window.contentLayoutRect); host frame \(host.frame); window frame \(window.frame)"
        )
    }

    func testEmptySetKeepsSearchBelowTitlebar() throws {
        let model = AppModel(uiFixture: try fixtureCatalog())
        model.selectSet(id: 2)
        let (window, host) = host(model)

        let search = try XCTUnwrap(
            descendants(of: host, matching: NSTextField.self)
                .first(where: { $0.placeholderString == "Search actions" })
        )

        XCTAssertTrue(window.contentLayoutRect.contains(search.convert(search.bounds, to: nil)))
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(
            descendants(of: host, matching: NSTextView.self)
                .contains(where: { $0.string.contains("tell application") })
        )
    }

    func testMinimumWidthKeepsCopyScriptVisibleInToolbar() throws {
        let model = AppModel(uiFixture: try fixtureCatalog())
        let (window, _) = host(model, width: 760)

        let visibleItems = window.toolbar?.visibleItems ?? []
        XCTAssertTrue(
            visibleItems.contains(where: { $0.itemIdentifier.rawValue == "copy-script" }),
            "Copy Script moved into overflow. Visible toolbar items: \(visibleItems.map(toolbarDescription))"
        )
    }

    func testSwitchingSetsReplacesActionRows() throws {
        let model = AppModel(uiFixture: try fixtureCatalog())
        let (_, host) = host(model)

        model.selectSet(id: 1)
        settle(host)

        let rowCounts = descendants(of: host, matching: NSTableView.self).map(\.numberOfRows)
        XCTAssertTrue(rowCounts.contains(6), "Expected a six-row actions table, got \(rowCounts)")
        XCTAssertFalse(rowCounts.contains(67), "The previous set's action rows were retained: \(rowCounts)")
    }

    private func fixtureCatalog() throws -> ActionCatalog {
        let longActions = (1...67)
            .map { #"{"name":"Long action \#($0)"}"# }
            .joined(separator: ",")
        let dropletActions = (1...6)
            .map { #"{"name":"Droplet action \#($0)"}"# }
            .joined(separator: ",")

        return try ActionCatalogParser.parse(
            #"{"sets":[{"name":"Long set","actions":[\#(longActions)]},{"name":"Droplets","actions":[\#(dropletActions)]},{"name":"Empty set","actions":[]}]}"#
        )
    }

    private func host(_ model: AppModel, width: CGFloat = 900) -> (NSWindow, NSHostingView<ContentView>) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Action Script Picker"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: ContentView(model: model))
        window.contentView = host
        window.setContentSize(NSSize(width: width, height: 560))
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        settle(host)
        return (window, host)
    }

    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
    }

    private func descendants<T: NSView>(of view: NSView, matching type: T.Type) -> [T] {
        var result = view is T ? [view as! T] : []
        for child in view.subviews {
            result.append(contentsOf: descendants(of: child, matching: type))
        }
        return result
    }

    private func colorDistance(_ left: NSColor?, _ right: NSColor?) -> CGFloat {
        guard let left, let right else { return 0 }
        let red = left.redComponent - right.redComponent
        let green = left.greenComponent - right.greenComponent
        let blue = left.blueComponent - right.blueComponent
        return sqrt((red * red) + (green * green) + (blue * blue))
    }

    private func toolbarDescription(_ item: NSToolbarItem) -> String {
        let labels = item.view.map {
            descendants(of: $0, matching: NSButton.self).compactMap { $0.accessibilityLabel() }
        } ?? []
        return ([item.itemIdentifier.rawValue, item.label, item.toolTip ?? ""] + labels)
            .joined(separator: " | ")
    }
}
