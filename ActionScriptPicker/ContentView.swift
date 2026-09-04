import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchIsFocused: Bool
    @State private var usesCompactToolbar = false

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 300, maxHeight: .infinity)
            actionPane
                .frame(minWidth: 220, idealWidth: 270, maxWidth: 400, maxHeight: .infinity)
            previewPane
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .frame(
            minWidth: 760,
            idealWidth: 900,
            maxWidth: .infinity,
            minHeight: 460,
            idealHeight: 560,
            maxHeight: .infinity
        )
        .background(WindowAccessor(usesCompactToolbar: $usesCompactToolbar))
        .toolbar { toolbarContent }
        .task { model.startIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .focusActionSearch)) { _ in
            searchIsFocused = true
        }
    }

    private var sidebar: some View {
        Group {
            if model.snapshot.catalog.sets.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No action sets")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            } else {
                List(selection: setSelection) {
                    ForEach(model.snapshot.catalog.sets) { set in
                        HStack(spacing: 7) {
                            Text(set.name.isEmpty ? String(localized: "Unnamed set") : set.name)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(set.actions.count, format: .number)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if AmbiguityAnalyzer.setIsAmbiguous(set, catalog: model.snapshot.catalog) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Ambiguous action set")
                            }
                        }
                        .tag(set.id)
                        .accessibilityLabel(setAccessibilityLabel(set))
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Action sets")
            }
        }
    }

    private var actionPane: some View {
        VStack(spacing: 0) {
            searchField
            actionStatusBanner
            actionPaneBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var actionStatusBanner: some View {
        if let issue = model.issue {
            IssueBanner(issue: issue, model: model)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        } else if model.status == .staleResults {
            staleClosedBanner
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var actionPaneBody: some View {
        if model.selectedTarget == nil {
            StatePane(
                symbol: "app.badge",
                title: "Photoshop not found",
                message: "Install Photoshop in an Applications folder or choose it from another location.",
                buttonTitle: "Choose Photoshop…",
                action: model.choosePhotoshop
            )
        } else if model.snapshot.catalog.sets.isEmpty && model.status == .photoshopClosed {
            StatePane(
                symbol: "power",
                title: "Photoshop is closed",
                message: "Open the selected Photoshop target to read its loaded actions.",
                buttonTitle: "Open Photoshop",
                action: model.openPhotoshop
            )
        } else if let set = model.selectedSet, set.actions.isEmpty {
            StatePane(
                symbol: "list.bullet.rectangle",
                title: "No actions in this set",
                message: "Choose another action set or add an action in Photoshop.",
                buttonTitle: nil,
                action: nil
            )
        } else if model.selectedSet != nil && model.filteredActions.isEmpty {
            StatePane(
                symbol: "magnifyingglass",
                title: "No matching actions",
                message: "Try a different search.",
                buttonTitle: nil,
                action: nil
            )
        } else if model.selectedSet != nil {
            actionList
        } else if model.isBusy {
            VStack(spacing: 10) {
                ProgressView()
                Text(model.status.label)
                    .foregroundStyle(.secondary)
            }
        } else {
            StatePane(
                symbol: "list.bullet.rectangle",
                title: "No loaded actions",
                message: "Refresh after Photoshop is ready.",
                buttonTitle: "Refresh",
                action: model.refresh
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search actions", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($searchIsFocused)
                .disabled(model.selectedSet == nil)
                .accessibilityLabel("Search actions")
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor)))
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actionList: some View {
        List(selection: actionSelection) {
            ForEach(model.filteredActions) { action in
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(action.name.isEmpty ? String(localized: "Unnamed action") : action.name)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let set = model.selectedSet,
                       AmbiguityAnalyzer.ambiguity(for: action, in: set, catalog: model.snapshot.catalog) != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Ambiguous action reference")
                    }
                }
                .tag(action.id)
                .accessibilityLabel(actionAccessibilityLabel(action))
            }
        }
        .listStyle(.inset)
        .accessibilityLabel("Actions")
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AppleScript Preview")
                        .font(.headline)
                    if let action = model.selectedAction {
                        Text(action.name.isEmpty ? String(localized: "Unnamed action") : action.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }

            if let ambiguity = model.selectedAmbiguity {
                InlineMessage(symbol: "exclamationmark.triangle.fill", text: ambiguity.message, color: .orange)
                Spacer(minLength: 0)
            } else if let script = model.generatedScript {
                SelectableTextView(text: script, accessibilityLabel: String(localized: "Generated AppleScript preview"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))

                if let note = model.pathTargetingNote {
                    InlineMessage(symbol: "location.fill", text: note, color: .secondary)
                }
            } else if model.selectedSet?.actions.isEmpty == true {
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: model.selectedAmbiguity == nil ? "chevron.left.forwardslash.chevron.right" : "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(previewPlaceholder)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(model.targets) { target in
                    Button {
                        model.selectTarget(id: target.id)
                    } label: {
                        if target.id == model.selectedTargetID {
                            Label(model.pickerLabel(for: target), systemImage: "checkmark")
                        } else {
                            Text(model.pickerLabel(for: target))
                        }
                    }
                }
                if !model.targets.isEmpty { Divider() }
                Button("Choose Photoshop…", action: model.choosePhotoshop)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "app.dashed")
                    Text(model.targetMenuLabel)
                        .lineLimit(1)
                }
                .frame(maxWidth: 220)
            }
            .disabled(!model.canSwitchTarget)
            .accessibilityLabel("Photoshop target")
        }

        ToolbarItem(placement: .automatic) {
            StatusView(status: model.status)
        }

        ToolbarItem(placement: .automatic) {
            Button(action: model.refresh) {
                if usesCompactToolbar {
                    Image(systemName: "arrow.clockwise")
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
            }
            .disabled(!model.canRefresh)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh loaded actions")
            .accessibilityLabel("Refresh")
        }

        ToolbarItem(id: "copy-script", placement: .confirmationAction) {
            Button(action: model.copyScript) {
                HStack(spacing: 5) {
                    Image(systemName: model.didCopy ? "checkmark" : "doc.on.doc")
                    Text(model.copyButtonLabel)
                }
            }
            .disabled(!model.canCopyScript)
            .help("Copy the generated AppleScript")
            .accessibilityLabel("Copy Script")
        }
    }

    private var setSelection: Binding<Int?> {
        Binding(get: { model.snapshot.selection.setID }, set: model.selectSet)
    }

    private var actionSelection: Binding<Int?> {
        Binding(get: { model.snapshot.selection.actionID }, set: model.selectAction)
    }

    private var staleClosedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Photoshop is closed. These results are stale.", systemImage: "clock.badge.exclamationmark")
                .font(.callout)
            Button("Open Photoshop", action: model.openPhotoshop)
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var previewPlaceholder: String {
        String(localized: "Select an action to preview its AppleScript.")
    }

    private func displaySetName(_ name: String) -> String {
        name.isEmpty ? String(localized: "Unnamed set") : name
    }

    private func setAccessibilityLabel(_ set: LoadedActionSet) -> String {
        let name = displaySetName(set.name)
        return String(localized: "\(name), \(set.actions.count) actions")
    }

    private func actionAccessibilityLabel(_ action: LoadedAction) -> String {
        let name = action.name.isEmpty ? String(localized: "Unnamed action") : action.name
        guard let set = model.selectedSet,
              AmbiguityAnalyzer.ambiguity(for: action, in: set, catalog: model.snapshot.catalog) != nil
        else { return name }
        return String(localized: "\(name), ambiguous action reference")
    }
}

private struct StatusView: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 5) {
            if status == .openingPhotoshop || status == .loadingActions {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.symbolName)
            }
            Text(status.label)
                .lineLimit(1)
        }
        .font(.callout)
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photoshop status: \(status.label)")
    }

    private var color: Color {
        switch status {
        case .connected: return .green
        case .openingPhotoshop, .loadingActions: return .accentColor
        case .photoshopMissing, .photoshopClosed: return .secondary
        case .staleResults: return .orange
        case .automationPermissionRequired, .timedOut, .queryFailed: return .red
        }
    }
}

private struct IssueBanner: View {
    let issue: AppIssue
    @ObservedObject var model: AppModel
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(issue.message, systemImage: symbol)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if issue.kind == .automationPermission {
                    Button("Open System Settings", action: model.openAutomationSettings)
                }
                if issue.kind != .incompatibleApplication {
                    Button("Retry", action: model.retry)
                }
            }
            .controlSize(.small)

            DisclosureGroup("Details", isExpanded: $showsDetails) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(issue.details)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Copy Details", action: model.copyIssueDetails)
                        .controlSize(.small)
                }
                .padding(.top, 5)
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        issue.kind == .automationPermission ? "lock.trianglebadge.exclamationmark" : "exclamationmark.triangle.fill"
    }
}

private struct StatePane: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let buttonTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .padding(.top, 3)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

private struct InlineMessage: View {
    let symbol: String
    let text: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

private struct SelectableTextView: NSViewRepresentable {
    let text: String
    let accessibilityLabel: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.setAccessibilityLabel(accessibilityLabel)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.setAccessibilityLabel(accessibilityLabel)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var usesCompactToolbar: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(usesCompactToolbar: $usesCompactToolbar)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.usesCompactToolbar = $usesCompactToolbar
        DispatchQueue.main.async { configure(nsView.window, coordinator: context.coordinator) }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ActionScriptPicker.MainWindow")
        window.minSize = NSSize(width: 760, height: 460)
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
        coordinator.observe(window)
    }

    @MainActor
    final class Coordinator: NSObject {
        var usesCompactToolbar: Binding<Bool>
        private weak var window: NSWindow?

        init(usesCompactToolbar: Binding<Bool>) {
            self.usesCompactToolbar = usesCompactToolbar
        }

        func observe(_ window: NSWindow) {
            if self.window !== window {
                NotificationCenter.default.removeObserver(self)
                self.window = window
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidResize(_:)),
                    name: NSWindow.didResizeNotification,
                    object: window
                )
            }
            updateTitleVisibility()
        }

        @objc private func windowDidResize(_ notification: Notification) {
            updateTitleVisibility()
        }

        private func updateTitleVisibility() {
            guard let window else { return }
            let isCompact = window.frame.width < 840
            window.titleVisibility = isCompact ? .hidden : .visible
            if usesCompactToolbar.wrappedValue != isCompact {
                usesCompactToolbar.wrappedValue = isCompact
            }
        }
    }
}
