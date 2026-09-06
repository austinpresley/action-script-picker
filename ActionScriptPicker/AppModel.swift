import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum ConnectionStatus: Equatable {
    case photoshopMissing
    case photoshopClosed
    case openingPhotoshop
    case loadingActions
    case connected
    case staleResults
    case automationPermissionRequired
    case timedOut
    case queryFailed

    var label: String {
        switch self {
        case .photoshopMissing: return String(localized: "Photoshop missing")
        case .photoshopClosed: return String(localized: "Photoshop closed")
        case .openingPhotoshop: return String(localized: "Opening Photoshop…")
        case .loadingActions: return String(localized: "Loading actions…")
        case .connected: return String(localized: "Connected")
        case .staleResults: return String(localized: "Stale results")
        case .automationPermissionRequired: return String(localized: "Automation permission required")
        case .timedOut: return String(localized: "Timed out")
        case .queryFailed: return String(localized: "Query failed")
        }
    }

    var symbolName: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .openingPhotoshop, .loadingActions: return "arrow.triangle.2.circlepath"
        case .photoshopMissing, .photoshopClosed: return "circle"
        case .staleResults: return "clock.badge.exclamationmark"
        case .automationPermissionRequired: return "lock.trianglebadge.exclamationmark"
        case .timedOut: return "timer"
        case .queryFailed: return "exclamationmark.triangle.fill"
        }
    }
}

struct AppIssue: Identifiable, Equatable {
    enum Kind: Equatable {
        case automationPermission
        case timeout
        case query
        case launch
        case incompatibleApplication
    }

    let id = UUID()
    let kind: Kind
    let message: String
    let details: String

    static func == (lhs: AppIssue, rhs: AppIssue) -> Bool {
        lhs.kind == rhs.kind && lhs.message == rhs.message && lhs.details == rhs.details
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var targets: [PhotoshopTarget] = []
    @Published private(set) var selectedTargetID: String?
    @Published private(set) var snapshot: RefreshSnapshot = .empty
    @Published var searchText = ""
    @Published private(set) var status: ConnectionStatus = .photoshopMissing
    @Published private(set) var issue: AppIssue?
    @Published private(set) var isBusy = false
    @Published private(set) var didCopy = false

    private let discovery: any TargetDiscovering
    private let queryService: any PhotoshopQuerying
    private let workspace: any WorkspaceProviding
    private var customTargetURL: URL?
    private var activeOperationID: UUID?
    private var copyResetTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false
#if UI_FIXTURE
    private var visualFixtureCatalog: ActionCatalog?
#endif

    init(
        discovery: any TargetDiscovering = PhotoshopTargetDiscovery(),
        queryService: any PhotoshopQuerying = NativePhotoshopQueryService(),
        workspace: any WorkspaceProviding = NSWorkspace.shared
    ) {
        self.discovery = discovery
        self.queryService = queryService
        self.workspace = workspace
        observePhotoshopLifecycle()
    }

#if DEBUG || UI_FIXTURE || TESTING
    convenience init(uiFixture catalog: ActionCatalog) {
        self.init(discovery: PhotoshopTargetDiscovery(roots: []))
#if UI_FIXTURE
        visualFixtureCatalog = catalog
#endif

        let targetURL = URL(fileURLWithPath: "/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app")
        let target = PhotoshopTarget(
            url: targetURL,
            canonicalPath: targetURL.path,
            applicationName: "Adobe Photoshop 2026",
            bundleIdentifier: PhotoshopTarget.sharedBundleIdentifier,
            releaseVersion: "27.10.0",
            buildVersion: "20260904",
            isBeta: false,
            isTested: true,
            locationRank: 0
        )

        targets = [target]
        selectedTargetID = target.id
        snapshot = RefreshReducer.success(
            previous: .empty,
            targetID: target.id,
            catalog: catalog
        )
        status = .connected
        started = true
    }
#endif

    deinit {
        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }
        copyResetTask?.cancel()
    }

    var selectedTarget: PhotoshopTarget? {
        guard let selectedTargetID else { return nil }
        return targets.first { $0.id == selectedTargetID }
    }

    var latestTarget: PhotoshopTarget? {
        TargetResolver.latestTarget(
            among: targets,
            sharedBundleResolvedURL: resolvedSharedBundleURL
        )
    }

    var selectedSet: LoadedActionSet? {
        guard let id = snapshot.selection.setID else { return nil }
        return snapshot.catalog.sets.first { $0.id == id }
    }

    var selectedAction: LoadedAction? {
        guard let id = snapshot.selection.actionID else { return nil }
        return selectedSet?.actions.first { $0.id == id }
    }

    var filteredActions: [LoadedAction] {
        guard let selectedSet else { return [] }
        return ActionSearch.filter(selectedSet.actions, query: searchText)
    }

    var selectedAmbiguity: Ambiguity? {
        guard let selectedSet, let selectedAction else { return nil }
        return AmbiguityAnalyzer.ambiguity(
            for: selectedAction,
            in: selectedSet,
            catalog: snapshot.catalog
        )
    }

    var generatedScript: String? {
        guard
            let target = selectedTarget,
            snapshot.dataTargetID == target.id,
            let selectedSet,
            let selectedAction,
            selectedAmbiguity == nil
        else { return nil }

        return AppleScriptGenerator.generate(
            actionName: selectedAction.name,
            setName: selectedSet.name,
            target: scriptAddress(for: target)
        )
    }

    var pathTargetingNote: String? {
        guard let target = selectedTarget else { return nil }
        if case .applicationPath = scriptAddress(for: target) {
            return String(localized: "This script targets this Photoshop installation. Regenerate it if the app moves.")
        }
        return nil
    }

    var canCopyScript: Bool {
        status == .connected && !snapshot.isStale && generatedScript != nil && !isBusy
    }

    /// What the generative mark is a fingerprint of. Two different action references must never
    /// produce the same token, so the two names are joined by a character neither can contain.
    var ribbonSignatureToken: String {
        // Nothing selected still deserves a mark, so the app signs with its own sentence. This
        // is a seed, not display text, and must not be localized: the shape has to be the same
        // one everywhere.
        guard let selectedSet else { return "An action. A script." }
        guard let selectedAction else { return selectedSet.name }
        return "\(selectedSet.name)\u{1}\(selectedAction.name)"
    }

    /// The mark reports the same state the rest of the window reports.
    var ribbonMood: RibbonMood {
        if didCopy { return .delivered }
        if isBusy { return .working }
        if issue != nil || snapshot.isStale || selectedAmbiguity != nil { return .unsettled }
        return canCopyScript ? .armed : .idle
    }

    var canRefresh: Bool { selectedTarget != nil && !isBusy }
    var canSwitchTarget: Bool { !isBusy }
    var copyButtonLabel: String { didCopy ? String(localized: "Copied") : String(localized: "Copy Script") }

    var targetMenuLabel: String {
        guard let selectedTarget else { return String(localized: "Choose Photoshop") }
        return pickerLabel(for: selectedTarget)
    }

    func pickerLabel(for target: PhotoshopTarget) -> String {
        let duplicateCount = targets.filter { $0.basePickerLabel == target.basePickerLabel }.count
        return duplicateCount > 1 ? "\(target.basePickerLabel): \(target.canonicalPath)" : target.basePickerLabel
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        rescanTargets(preserveSelection: false)
        guard let target = selectedTarget else {
            status = .photoshopMissing
            return
        }
        if isRunning(target) {
            requestLoad(for: target)
        } else {
            status = .photoshopClosed
        }
    }

    func refresh() {
        guard !isBusy else { return }
#if UI_FIXTURE
        if let visualFixtureCatalog, let selectedTargetID {
            isBusy = true
            status = .loadingActions
            didCopy = false
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                snapshot = RefreshReducer.success(previous: snapshot, targetID: selectedTargetID, catalog: visualFixtureCatalog)
                status = .connected
                isBusy = false
            }
            return
        }
#endif
        rescanTargets(preserveSelection: true)
        guard let target = selectedTarget else {
            snapshot = .empty
            status = .photoshopMissing
            return
        }

        if isRunning(target) {
            requestLoad(for: target)
        } else {
            markClosed(for: target)
        }
    }

    func selectTarget(id: String) {
        guard !isBusy, selectedTargetID != id, let target = targets.first(where: { $0.id == id }) else { return }
        selectedTargetID = id
        searchText = ""
        issue = nil
        didCopy = false

        if snapshot.dataTargetID != target.id {
            snapshot = .empty
        }

        if isRunning(target) {
            requestLoad(for: target)
        } else {
            status = .photoshopClosed
        }
    }

    func selectSet(id: Int?) {
        guard snapshot.selection.setID != id else { return }
        snapshot.selection.setID = id
        snapshot.selection.actionID = snapshot.catalog.sets.first(where: { $0.id == id })?.actions.first?.id
        searchText = ""
        didCopy = false
    }

    func selectAction(id: Int?) {
        snapshot.selection.actionID = id
        didCopy = false
    }

    func choosePhotoshop() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Photoshop")
        panel.message = String(localized: "Choose a compatible Adobe Photoshop application.")
        panel.prompt = String(localized: "Choose")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let inspected = discovery.inspectApplication(at: url, locationRank: 2) else {
            issue = AppIssue(
                kind: .incompatibleApplication,
                message: String(localized: "That application is not a compatible Photoshop target."),
                details: String(localized: "Choose an Adobe Photoshop application that exposes the \"do javascript\" and \"do action\" AppleScript commands.")
            )
            return
        }

        customTargetURL = inspected.url
        rescanTargets(preserveSelection: true)
        selectTarget(id: inspected.id)
    }

    func openPhotoshop() {
        guard !isBusy, let target = selectedTarget else { return }
        let operationID = UUID()
        activeOperationID = operationID
        isBusy = true
        issue = nil
        status = .openingPhotoshop

        Task {
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.addsToRecentItems = false
                let running = try await workspace.openApplication(at: target.url, configuration: configuration)

                let deadline = Date().addingTimeInterval(60)
                while !running.isFinishedLaunching && Date() < deadline {
                    try await Task.sleep(nanoseconds: 250_000_000)
                }

                guard activeOperationID == operationID else { return }
                guard running.isFinishedLaunching else {
                    finishOpeningWithTimeout(operationID: operationID)
                    return
                }

                isBusy = false
                requestLoad(for: target)
            } catch is CancellationError {
                finishOperationIfCurrent(operationID)
            } catch {
                guard activeOperationID == operationID else { return }
                isBusy = false
                activeOperationID = nil
                status = .queryFailed
                issue = AppIssue(
                    kind: .launch,
                    message: String(localized: "Photoshop could not be opened."),
                    details: error.localizedDescription
                )
            }
        }
    }

    func retry() {
        guard !isBusy, let target = selectedTarget else { return }
        if isRunning(target) {
            requestLoad(for: target)
        } else {
            status = .photoshopClosed
        }
    }

    func copyScript() {
        guard canCopyScript, let generatedScript else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(generatedScript, forType: .string) else { return }

        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    func copyIssueDetails() {
        guard let issue else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(issue.details, forType: .string)
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func focusSearch() {
        NotificationCenter.default.post(name: .focusActionSearch, object: nil)
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var resolvedSharedBundleURL: URL? {
        workspace.urlForApplication(withBundleIdentifier: PhotoshopTarget.sharedBundleIdentifier)
    }

    private func scriptAddress(for target: PhotoshopTarget) -> PhotoshopTargetAddress {
        TargetResolver.scriptAddress(
            for: target,
            latest: latestTarget
        )
    }

    private func rescanTargets(preserveSelection: Bool) {
        let priorID = preserveSelection ? selectedTargetID : nil
        targets = discovery.discover(customURL: customTargetURL)

        if let priorID, targets.contains(where: { $0.id == priorID }) {
            selectedTargetID = priorID
        } else {
            selectedTargetID = TargetResolver.latestTarget(
                among: targets,
                sharedBundleResolvedURL: resolvedSharedBundleURL
            )?.id
        }

        if let selectedTargetID, snapshot.dataTargetID != nil, snapshot.dataTargetID != selectedTargetID {
            snapshot = .empty
        }
    }

    private func requestLoad(for target: PhotoshopTarget) {
        guard !isBusy else { return }
        let operationID = UUID()
        activeOperationID = operationID
        isBusy = true
        issue = nil
        didCopy = false
        status = .loadingActions

        Task {
            do {
                let catalog = try await queryService.query(target: target)
                guard activeOperationID == operationID, selectedTargetID == target.id else { return }

                snapshot = RefreshReducer.success(
                    previous: snapshot,
                    targetID: target.id,
                    catalog: catalog
                )
                activeOperationID = nil
                isBusy = false
                status = .connected
            } catch {
                guard activeOperationID == operationID, selectedTargetID == target.id else { return }
                snapshot = RefreshReducer.failure(previous: snapshot, targetID: target.id)
                activeOperationID = nil
                isBusy = false
                issue = issue(for: error)
                status = snapshot.isStale ? .staleResults : status(for: error)
            }
        }
    }

    private func issue(for error: Error) -> AppIssue {
        if let queryError = error as? PhotoshopQueryError {
            switch queryError {
            case .automationPermissionDenied:
                return AppIssue(
                    kind: .automationPermission,
                    message: queryError.localizedDescription,
                    details: queryError.details
                )
            case .timedOut:
                return AppIssue(kind: .timeout, message: queryError.localizedDescription, details: queryError.details)
            default:
                return AppIssue(kind: .query, message: queryError.localizedDescription, details: queryError.details)
            }
        }
        if let parsingError = error as? CatalogParsingError {
            return AppIssue(kind: .query, message: parsingError.localizedDescription, details: parsingError.details)
        }
        return AppIssue(kind: .query, message: String(localized: "Photoshop could not return its loaded actions."), details: error.localizedDescription)
    }

    private func status(for error: Error) -> ConnectionStatus {
        guard let queryError = error as? PhotoshopQueryError else { return .queryFailed }
        switch queryError {
        case .automationPermissionDenied: return .automationPermissionRequired
        case .timedOut: return .timedOut
        default: return .queryFailed
        }
    }

    private func markClosed(for target: PhotoshopTarget) {
        snapshot = RefreshReducer.failure(previous: snapshot, targetID: target.id)
        issue = nil
        status = snapshot.isStale ? .staleResults : .photoshopClosed
    }

    private func finishOpeningWithTimeout(operationID: UUID) {
        guard activeOperationID == operationID else { return }
        isBusy = false
        activeOperationID = nil
        snapshot = RefreshReducer.failure(previous: snapshot, targetID: selectedTargetID ?? "")
        issue = AppIssue(
            kind: .timeout,
            message: String(localized: "Photoshop did not finish opening within 60 seconds."),
            details: "The Photoshop launch exceeded the 60-second timeout."
        )
        status = snapshot.isStale ? .staleResults : .timedOut
    }

    private func finishOperationIfCurrent(_ operationID: UUID) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        isBusy = false
    }

    private func isRunning(_ target: PhotoshopTarget) -> Bool {
        runningApplication(for: target) != nil
    }

    private func runningApplication(for target: PhotoshopTarget) -> NSRunningApplication? {
        workspace.runningApplications.first { application in
            application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == target.canonicalPath
        }
    }

    private func observePhotoshopLifecycle() {
        let center = workspace.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.applicationDidLaunch(notification) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.applicationDidTerminate(notification) }
        })
    }

    private func applicationDidLaunch(_ notification: Notification) {
        guard !isBusy,
              let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let target = selectedTarget,
              application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == target.canonicalPath
        else { return }
        requestLoad(for: target)
    }

    private func applicationDidTerminate(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let target = selectedTarget,
            application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == target.canonicalPath
        else { return }

        activeOperationID = nil
        isBusy = false
        markClosed(for: target)
    }
}

extension Notification.Name {
    static let focusActionSearch = Notification.Name("ActionScriptPicker.focusActionSearch")
}
