import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchIsFocused: Bool
    @State private var usesCompactToolbar = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                sidebar(artworkHeight: min(148, max(48, geometry.size.height - 430)))
                    .frame(minWidth: 220, idealWidth: 230, maxWidth: 300, maxHeight: .infinity)
                actionPane
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 400, maxHeight: .infinity)
                previewPane
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
        }
        .frame(
            minWidth: 760,
            idealWidth: 1040,
            maxWidth: .infinity,
            minHeight: 460,
            idealHeight: 640,
            maxHeight: .infinity
        )
        .foregroundStyle(PickerStyle.ink)
        .tint(PickerStyle.accent)
        .accentColor(PickerStyle.accent)
        .background(PickerStyle.paper)
        .background(WindowAccessor(usesCompactToolbar: $usesCompactToolbar))
        .toolbar { toolbarContent }
        .task { model.startIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .focusActionSearch)) { _ in
            searchIsFocused = true
        }
    }

    private func sidebar(artworkHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                PickerMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Action Script")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.3)
                    Text("PICKER")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(2.8)
                        .foregroundStyle(PickerStyle.secondary)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 85, alignment: .center)
            .accessibilityElement(children: .combine)

            HStack {
                Eyebrow("ACTION SETS")
                Spacer()
                CountBadge(count: model.snapshot.catalog.sets.count)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            if model.snapshot.catalog.sets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 23, weight: .light))
                    Text("No action sets")
                        .font(.system(size: 12))
                }
                .foregroundStyle(PickerStyle.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else {
                List(selection: setSelection) {
                    ForEach(model.snapshot.catalog.sets) { set in
                        HStack(spacing: 9) {
                            Image(systemName: model.snapshot.selection.setID == set.id ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                                .font(.system(size: 13, weight: .regular))
                                .frame(width: 18)
                            Text(displaySetName(set.name))
                                .font(.system(size: 12, weight: model.snapshot.selection.setID == set.id ? .semibold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            CountBadge(count: set.actions.count)
                            if AmbiguityAnalyzer.setIsAmbiguous(set, catalog: model.snapshot.catalog) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Ambiguous action set")
                            }
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .modifier(PickerRowSurface(selected: model.snapshot.selection.setID == set.id))
                        .tag(set.id)
                        .help(displaySetName(set.name))
                        .accessibilityLabel(setAccessibilityLabel(set))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Action sets")
            }

            VStack(spacing: 7) {
                ScriptRibbon(token: model.ribbonSignatureToken, mood: model.ribbonMood)
                    .frame(height: artworkHeight)
                HStack(spacing: 7) {
                    Text("PHOTOSHOP")
                    Image(systemName: "arrow.right")
                    Text("APPLESCRIPT")
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(PickerStyle.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                Text("\(model.snapshot.catalog.sets.reduce(0) { $0 + $1.actions.count }) loaded actions")
            }
            .font(.system(size: 10))
            .foregroundStyle(PickerStyle.secondary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(PickerStyle.rule).frame(height: 1) }
        }
        .background(PickerStyle.sidebar)
    }

    private var actionPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow("LOADED ACTIONS")
                HStack(alignment: .firstTextBaseline) {
                    Text(model.selectedSet.map { displaySetName($0.name) } ?? String(localized: "Actions"))
                        .font(.system(size: 19, weight: .semibold))
                        .tracking(-0.5)
                        .lineLimit(1)
                        .help(model.selectedSet.map { displaySetName($0.name) } ?? String(localized: "Actions"))
                    Spacer(minLength: 4)
                    CountBadge(count: model.filteredActions.count)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 85, alignment: .center)
            searchField
            actionStatusBanner
            actionPaneBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 5) {
                Image(systemName: "cursorarrow")
                Text("Select an action to preview")
            }
            .font(.system(size: 10))
            .foregroundStyle(PickerStyle.secondary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .overlay(alignment: .top) { Rectangle().fill(PickerStyle.rule).frame(height: 1) }
        }
        .background(PickerStyle.paper)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(searchIsFocused ? PickerStyle.accent : PickerStyle.secondary)
            TextField("Search actions", text: $model.searchText)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .focused($searchIsFocused)
                .disabled(model.selectedSet == nil)
                .accessibilityLabel("Search actions")
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PickerStyle.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else {
                Text("⌘F")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PickerStyle.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(PickerStyle.editor, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(searchIsFocused ? PickerStyle.accent : PickerStyle.rule, lineWidth: searchIsFocused ? 1.5 : 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: searchIsFocused)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actionList: some View {
        List(selection: actionSelection) {
            ForEach(model.filteredActions) { action in
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .medium))
                        .frame(width: 26, height: 28)
                        .background(PickerStyle.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityHidden(true)
                    Text(action.name.isEmpty ? String(localized: "Unnamed action") : action.name)
                        .font(.system(size: 12, weight: model.snapshot.selection.actionID == action.id ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let set = model.selectedSet,
                       AmbiguityAnalyzer.ambiguity(for: action, in: set, catalog: model.snapshot.catalog) != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Ambiguous action reference")
                    } else if model.snapshot.selection.actionID == action.id {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .modifier(PickerRowSurface(selected: model.snapshot.selection.actionID == action.id))
                .tag(action.id)
                .help(action.name.isEmpty ? String(localized: "Unnamed action") : action.name)
                .accessibilityLabel(actionAccessibilityLabel(action))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Actions")
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            previewHeading

            if let ambiguity = model.selectedAmbiguity {
                InlineMessage(symbol: "exclamationmark.triangle.fill", text: ambiguity.message, color: .orange)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                previewArtwork
            } else if let script = model.generatedScript {
                ScriptPreview(script: script, didCopy: model.didCopy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let note = model.pathTargetingNote {
                    InlineMessage(symbol: "location.fill", text: note, color: PickerStyle.secondary)
                }
                copyFooter
            } else {
                previewArtwork
            }
        }
        .padding(24)
        .background(PickerStyle.panel)
    }

    private var previewHeading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("APPLESCRIPT PREVIEW")
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedAction.map { $0.name.isEmpty ? String(localized: "Unnamed action") : $0.name } ?? String(localized: "An action. A script."))
                    .font(.system(size: 29, weight: .regular, design: .serif))
                    .tracking(-0.7)
                    .lineLimit(1)
                    .help(model.selectedAction?.name ?? String(localized: "Select an action to preview its AppleScript."))
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .accessibilityHidden(true)
                    Text(model.selectedSet.map { displaySetName($0.name) } ?? String(localized: "Your Photoshop actions, ready to use elsewhere."))
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(PickerStyle.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var copyFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copyFooterTitle)
                        .font(.system(size: 12, weight: .medium))
                    Text("Script Editor, Shortcuts, Stream Deck.")
                        .font(.system(size: 10))
                        .foregroundStyle(PickerStyle.secondary)
                }
                .fixedSize()
                Spacer(minLength: 0)
                copyButton
            }
            HStack {
                copyButton
                Spacer(minLength: 8)
                Text("⇧⌘C")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PickerStyle.secondary)
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var copyButton: some View {
        Button(action: model.copyScript) {
            HStack(spacing: 7) {
                Image(systemName: model.didCopy ? "checkmark" : "doc.on.doc")
                Text(model.copyButtonLabel)
            }
            .frame(width: 92)
        }
        .buttonStyle(PickerButtonStyle(prominent: true))
        .fixedSize()
        .disabled(!model.canCopyScript)
        .help("Copy the generated AppleScript. Shift-Command-C.")
        .accessibilityLabel("Copy Script")
    }

    private var copyFooterTitle: String {
        if model.didCopy { return String(localized: "Copied to clipboard") }
        if model.canCopyScript { return String(localized: "Take it into your workflow") }
        return model.isBusy
            ? String(localized: "Waiting for Photoshop")
            : String(localized: "Refresh to copy this script")
    }

    private var previewArtwork: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                ScriptRibbon(token: model.ribbonSignatureToken, mood: model.ribbonMood)
                    .frame(width: min(260, geometry.size.width), height: min(190, geometry.size.height * 0.5))
                VStack(spacing: 7) {
                    Text(model.selectedAmbiguity != nil ? "Choose a unique action" : "Your next shortcut starts here.")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                    Text(previewPlaceholder)
                        .font(.system(size: 12))
                        .foregroundStyle(PickerStyle.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            sourceToolbarItem.sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            coffeeToolbarItem.sharedBackgroundVisibility(.hidden)
        } else {
            sourceToolbarItem
            ToolbarItem(id: "toolbar-spacer", placement: .principal) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
            coffeeToolbarItem
        }
    }

    private var sourceToolbarItem: some ToolbarContent {
        ToolbarItem(id: "photoshop-target", placement: .navigation) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(PickerStyle.accent)
                        .frame(width: 34, height: 34)
                        .background(PickerStyle.accentWash.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
#if UI_FIXTURE
                        Eyebrow("SAMPLE ACTIONS")
#else
                        Eyebrow("SOURCE APPLICATION")
#endif
                        sourceMenu
                    }
                }
                .frame(width: usesCompactToolbar ? 235 : 285, alignment: .leading)

                Rectangle()
                    .fill(PickerStyle.rule)
                    .frame(width: 1, height: 26)
                    .accessibilityHidden(true)

                StatusView(status: model.status, compact: usesCompactToolbar)
                    .help(model.status.label)

                refreshButton
            }
            .padding(.horizontal, 7)
            .frame(height: 46, alignment: .leading)
        }
    }

    private var sourceMenu: some View {
        Menu {
#if UI_FIXTURE
            Text("Example actions for the design preview")
            Button("Reload sample actions", action: model.refresh)
#else
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
#endif
        } label: {
            Text(model.targetMenuLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PickerStyle.ink)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .disabled(!model.canSwitchTarget)
        .help(model.targetMenuLabel)
        .accessibilityLabel("Photoshop target")
    }

    private var refreshButton: some View {
        Button(action: model.refresh) {
            RefreshGlyph(isBusy: model.isBusy)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(PickerButtonStyle())
        .disabled(!model.canRefresh)
        .keyboardShortcut("r", modifiers: .command)
        .help("Refresh loaded actions. Command-R.")
        .accessibilityLabel("Refresh")
    }

    private var coffeeToolbarItem: some ToolbarContent {
        ToolbarItem(id: "buy-me-a-coffee", placement: .confirmationAction) {
            Link(destination: URL(string: "https://buymeacoffee.com/apresley")!) {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PickerButtonStyle())
            .help("Support Action Script Picker")
            .accessibilityHint("Opens buymeacoffee.com/apresley in your browser")
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
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            if status == .openingPhotoshop || status == .loadingActions {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.symbolName)
            }
            if !compact {
                Text(status.label)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photoshop status: \(status.label)")
    }

    private var color: Color {
        switch status {
        case .connected: return PickerStyle.success
        case .openingPhotoshop, .loadingActions: return PickerStyle.accent
        case .photoshopMissing, .photoshopClosed: return PickerStyle.secondary
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
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(PickerStyle.accent)
                .frame(width: 62, height: 62)
                .background(PickerStyle.accentWash.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                .padding(.bottom, 8)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(PickerButtonStyle())
                    .padding(.top, 8)
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
            .font(.system(size: 11))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
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
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(PickerStyle.paper)
        window.toolbarStyle = .unified
        if #unavailable(macOS 15.0) { window.toolbar?.showsBaselineSeparator = false }
        window.styleMask.remove(.fullSizeContentView)
        if let contentView = window.contentView {
            configureLists(in: contentView)
        }
        coordinator.observe(window)
    }

    private func configureLists(in view: NSView) {
        if let table = view as? NSTableView {
            // SwiftUI draws the selection; AppKit still owns focus, keyboard navigation, and accessibility.
            table.selectionHighlightStyle = .none
        }
        for child in view.subviews { configureLists(in: child) }
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
            let isCompact = window.frame.width < 920
            window.titleVisibility = .hidden
            if usesCompactToolbar.wrappedValue != isCompact {
                usesCompactToolbar.wrappedValue = isCompact
            }
        }
    }
}
