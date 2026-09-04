import Foundation
import XCTest

final class PhotoshopTargetDiscoveryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDiscoversNestedPhotoshopAndDoesNotDescendIntoOtherApps() throws {
        let nested = temporaryDirectory
            .appendingPathComponent("Adobe Photoshop 2026", isDirectory: true)
            .appendingPathComponent("Adobe Photoshop 2026.app", isDirectory: true)
        try makeApplication(at: nested, name: "Adobe Photoshop 2026", release: "27.1", build: "90")

        let hiddenInsideAnotherApp = temporaryDirectory
            .appendingPathComponent("Unrelated.app/Contents/PlugIns/Adobe Photoshop 2026.app", isDirectory: true)
        try makeApplication(at: hiddenInsideAnotherApp, name: "Adobe Photoshop 2026", release: "27.2", build: "91")

        let discovery = PhotoshopTargetDiscovery(roots: [(temporaryDirectory, 0)])
        let targets = discovery.discover(customURL: nil)

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].canonicalPath, nested.path)
    }

    func testFiltersApplicationsWithoutRequiredCommands() throws {
        let incompatible = temporaryDirectory.appendingPathComponent("Adobe Photoshop 2026.app", isDirectory: true)
        try makeApplication(
            at: incompatible,
            name: "Adobe Photoshop 2026",
            release: "27.0",
            build: "1",
            scriptingDefinition: #"<dictionary><command name="do javascript"/></dictionary>"#
        )

        XCTAssertTrue(PhotoshopTargetDiscovery(roots: [(temporaryDirectory, 0)]).discover(customURL: nil).isEmpty)
    }

    func testClassifiesStableBetaAndTestedRelease() throws {
        let stable = temporaryDirectory.appendingPathComponent("Adobe Photoshop 2026.app", isDirectory: true)
        let beta = temporaryDirectory.appendingPathComponent("Adobe Photoshop (Beta).app", isDirectory: true)
        try makeApplication(at: stable, name: "Adobe Photoshop 2026", release: "27.0", build: "1")
        try makeApplication(at: beta, name: "Adobe Photoshop (Beta)", bundleID: "com.adobe.PhotoshopBeta", release: "28.0", build: "1")

        let targets = PhotoshopTargetDiscovery(roots: [(temporaryDirectory, 0)]).discover(customURL: nil)
        let stableTarget = try XCTUnwrap(targets.first { !$0.isBeta })
        let betaTarget = try XCTUnwrap(targets.first { $0.isBeta })

        XCTAssertTrue(stableTarget.isTested)
        XCTAssertFalse(betaTarget.isTested)
        XCTAssertTrue(betaTarget.basePickerLabel.contains("Beta"))
        XCTAssertTrue(betaTarget.basePickerLabel.contains("Untested"))
    }

    func testLatestTargetUsesNumericReleaseAndBuildOrdering() throws {
        let older = try target(path: "/Applications/Older.app", release: "27.9", build: "999")
        let newerLowBuild = try target(path: "/Applications/Newer A.app", release: "27.10", build: "9")
        let newerHighBuild = try target(path: "/Applications/Newer B.app", release: "27.10", build: "10")

        let latest = TargetResolver.latestTarget(
            among: [older, newerLowBuild, newerHighBuild],
            sharedBundleResolvedURL: nil
        )

        XCTAssertEqual(latest?.id, newerHighBuild.id)
    }

    func testStableTargetWinsOverNewerBeta() throws {
        let stable = try target(path: "/Applications/Stable.app", release: "27.0", build: "1")
        let beta = try target(path: "/Applications/Beta.app", release: "99.0", build: "1", isBeta: true)

        XCTAssertEqual(TargetResolver.latestTarget(among: [beta, stable], sharedBundleResolvedURL: nil)?.id, stable.id)
    }

    func testTieBreakingPrefersResolvedPathThenApplicationsLocation() throws {
        let system = try target(path: "/Applications/System.app", release: "27.0", build: "1", locationRank: 0)
        let user = try target(path: "/Users/test/Applications/User.app", release: "27.0", build: "1", locationRank: 1)

        XCTAssertEqual(
            TargetResolver.latestTarget(among: [system, user], sharedBundleResolvedURL: user.url)?.id,
            user.id
        )
        XCTAssertEqual(
            TargetResolver.latestTarget(among: [system, user], sharedBundleResolvedURL: nil)?.id,
            system.id
        )
    }

    func testScriptTargetingUsesSharedBundleIdentityForLatestByDefault() throws {
        let latest = try target(path: "/Applications/Latest.app", release: "27.0", build: "2")
        let older = try target(path: "/Applications/Older.app", release: "26.0", build: "1")

        XCTAssertEqual(
            TargetResolver.scriptAddress(for: latest, latest: latest),
            .bundleIdentifier("com.adobe.Photoshop")
        )
        XCTAssertEqual(
            TargetResolver.scriptAddress(for: older, latest: latest),
            .applicationPath(older.canonicalPath)
        )
    }

    private func makeApplication(
        at url: URL,
        name: String,
        bundleID: String = "com.adobe.Photoshop",
        release: String,
        build: String,
        scriptingDefinition: String = #"<dictionary><suite><command name="do javascript"/><command name="do action"/></suite></dictionary>"#
    ) throws {
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": release,
            "CFBundleVersion": build,
            "CFBundlePackageType": "APPL"
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data(scriptingDefinition.utf8).write(to: resources.appendingPathComponent("Photoshop.sdef"))
    }

    private func target(
        path: String,
        release: String,
        build: String,
        isBeta: Bool = false,
        locationRank: Int = 0
    ) throws -> PhotoshopTarget {
        let url = URL(fileURLWithPath: path)
        return PhotoshopTarget(
            url: url,
            canonicalPath: url.path,
            applicationName: isBeta ? "Adobe Photoshop Beta" : "Adobe Photoshop",
            bundleIdentifier: "com.adobe.Photoshop",
            releaseVersion: release,
            buildVersion: build,
            isBeta: isBeta,
            isTested: NumericVersion(release).components.first == 27 && !isBeta,
            locationRank: locationRank
        )
    }
}
