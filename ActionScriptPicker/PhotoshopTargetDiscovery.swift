import AppKit
import Foundation

struct NumericVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init(_ rawValue: String) {
        components = rawValue
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }

    static func < (lhs: NumericVersion, rhs: NumericVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct PhotoshopTarget: Identifiable, Equatable, Sendable {
    static let sharedBundleIdentifier = "com.adobe.Photoshop"

    let url: URL
    let canonicalPath: String
    let applicationName: String
    let bundleIdentifier: String
    let releaseVersion: String
    let buildVersion: String
    let isBeta: Bool
    let isTested: Bool
    let locationRank: Int

    var id: String { canonicalPath }

    var basePickerLabel: String {
        var qualifiers: [String] = []
        if isBeta { qualifiers.append(String(localized: "Beta")) }
        if !isTested { qualifiers.append(String(localized: "Untested")) }

        let version = releaseVersion.isEmpty ? String(localized: "Unknown version") : releaseVersion
        let suffix = qualifiers.isEmpty ? "" : " (\(qualifiers.joined(separator: ", ")))"
        return "\(applicationName) \(version)\(suffix)"
    }
}

protocol TargetDiscovering {
    func discover(customURL: URL?) -> [PhotoshopTarget]
    func inspectApplication(at url: URL, locationRank: Int) -> PhotoshopTarget?
}

struct PhotoshopTargetDiscovery: TargetDiscovering {
    let roots: [(url: URL, rank: Int)]
    let fileManager: FileManager

    init(
        roots: [(url: URL, rank: Int)] = [
            (URL(fileURLWithPath: "/Applications", isDirectory: true), 0),
            (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true), 1)
        ],
        fileManager: FileManager = .default
    ) {
        self.roots = roots
        self.fileManager = fileManager
    }

    func discover(customURL: URL?) -> [PhotoshopTarget] {
        var targetsByPath: [String: PhotoshopTarget] = [:]

        for root in roots where fileManager.fileExists(atPath: root.url.path) {
            guard let enumerator = fileManager.enumerator(
                at: root.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }
                enumerator.skipDescendants()
                if let target = inspectApplication(at: url, locationRank: root.rank) {
                    targetsByPath[target.canonicalPath] = target
                }
            }
        }

        if let customURL, let target = inspectApplication(at: customURL, locationRank: 2) {
            targetsByPath[target.canonicalPath] = target
        }

        return targetsByPath.values.sorted { $0.canonicalPath.localizedStandardCompare($1.canonicalPath) == .orderedAscending }
    }

    func inspectApplication(at url: URL, locationRank: Int) -> PhotoshopTarget? {
        let applicationURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier.lowercased().hasPrefix("com.adobe.photoshop")
        else { return nil }

        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        guard name.localizedCaseInsensitiveContains("Adobe Photoshop"),
              hasRequiredScriptingCommands(in: applicationURL)
        else { return nil }

        let release = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        let pathAndName = "\(name) \(applicationURL.path)"
        let isBeta = pathAndName.localizedCaseInsensitiveContains("beta")
        let isTested = NumericVersion(release).components.first == 27 && !isBeta

        return PhotoshopTarget(
            url: applicationURL,
            canonicalPath: applicationURL.path,
            applicationName: name,
            bundleIdentifier: bundleIdentifier,
            releaseVersion: release,
            buildVersion: build,
            isBeta: isBeta,
            isTested: isTested,
            locationRank: locationRank
        )
    }

    private func hasRequiredScriptingCommands(in applicationURL: URL) -> Bool {
        let resourcesURL = applicationURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: resourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return false }

        for case let url as URL in enumerator where url.pathExtension.caseInsensitiveCompare("sdef") == .orderedSame {
            guard let data = fileManager.contents(atPath: url.path),
                  let definition = String(data: data, encoding: .utf8)?.lowercased()
            else { continue }
            if definition.contains("do javascript") && definition.contains("do action") {
                return true
            }
        }
        return false
    }
}

enum TargetResolver {
    static func latestTarget(
        among targets: [PhotoshopTarget],
        sharedBundleResolvedURL: URL?
    ) -> PhotoshopTarget? {
        let stable = targets.filter { !$0.isBeta }
        let candidates = stable.isEmpty ? targets.filter(\.isBeta) : stable
        let resolvedPath = sharedBundleResolvedURL?.resolvingSymlinksInPath().standardizedFileURL.path

        return candidates.sorted { left, right in
            let leftRelease = NumericVersion(left.releaseVersion)
            let rightRelease = NumericVersion(right.releaseVersion)
            if leftRelease != rightRelease { return leftRelease > rightRelease }

            let leftBuild = NumericVersion(left.buildVersion)
            let rightBuild = NumericVersion(right.buildVersion)
            if leftBuild != rightBuild { return leftBuild > rightBuild }

            let leftResolves = left.canonicalPath == resolvedPath
            let rightResolves = right.canonicalPath == resolvedPath
            if leftResolves != rightResolves { return leftResolves }

            if left.locationRank != right.locationRank { return left.locationRank < right.locationRank }
            return left.canonicalPath.localizedStandardCompare(right.canonicalPath) == .orderedAscending
        }.first
    }

    static func scriptAddress(
        for selected: PhotoshopTarget,
        latest: PhotoshopTarget?
    ) -> PhotoshopTargetAddress {
        if selected.id == latest?.id,
           selected.bundleIdentifier == PhotoshopTarget.sharedBundleIdentifier {
            return .bundleIdentifier(PhotoshopTarget.sharedBundleIdentifier)
        }
        return .applicationPath(selected.canonicalPath)
    }
}

protocol WorkspaceProviding: AnyObject {
    var notificationCenter: NotificationCenter { get }
    var runningApplications: [NSRunningApplication] { get }
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func openApplication(at applicationURL: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication
}

extension NSWorkspace: WorkspaceProviding {}
