import AppKit
import SwiftUI

@main
struct ActionScriptPickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
#if UI_FIXTURE
        _model = StateObject(wrappedValue: AppModel(uiFixture: .visualFixture))
#else
        _model = StateObject(wrappedValue: AppModel())
#endif
    }

    var body: some Scene {
        WindowGroup("Action Script Picker") {
            ContentView(model: model)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Show Window") {
                    model.showWindow()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("Actions") {
                Button("Refresh") {
                    model.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canRefresh)

                Button("Focus Search") {
                    model.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button(model.copyButtonLabel) {
                    model.copyScript()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canCopyScript)
            }
        }
    }
}

#if UI_FIXTURE
private extension ActionCatalog {
    static var visualFixture: ActionCatalog {
        ActionCatalog(sets: [
            fixtureSet(id: 0, name: "Portrait Retouch", actions: [
                "Skin Cleanup",
                "Dodge and Burn",
                "Reduce Shine",
                "Brighten Eyes",
                "Whiten Teeth"
            ]),
            fixtureSet(id: 1, name: "Color and Tone", actions: [
                "Soft Contrast",
                "Warm Highlights",
                "Cool Shadows",
                "Film Fade"
            ]),
            fixtureSet(id: 2, name: "Subject and Background", actions: [
                "Select Subject",
                "Clean Background",
                "Background Blur"
            ]),
            fixtureSet(id: 3, name: "Resize", actions: [
                "Web Landscape",
                "Web Portrait",
                "Instagram Square"
            ]),
            fixtureSet(id: 4, name: "Export", actions: [
                "Save JPEG",
                "Save PNG",
                "Export Contact Sheet"
            ])
        ])
    }

    static func fixtureSet(id: Int, name: String, actions: [String]) -> LoadedActionSet {
        LoadedActionSet(
            id: id,
            name: name,
            actions: actions.enumerated().map { index, name in
                LoadedAction(id: index, name: name)
            }
        )
    }
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
