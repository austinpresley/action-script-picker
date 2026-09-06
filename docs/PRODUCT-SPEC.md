# Action Script Picker product specification

Status: Accepted on 2026-09-03

## Product goal

Action Script Picker is a small native macOS utility that reads the action sets and actions currently loaded in Adobe Photoshop and generates a ready-to-paste AppleScript for one selected action.

The app reads, selects, previews, and copies. It never runs an action.

## Product boundaries

Version 1:

- Reads only the contents of the selected Photoshop target's live Actions panel.
- Does not scan, load, import, edit, or save `.atn` files.
- Does not run Photoshop actions.
- Does not provide favorites, recent actions, sample data, or a saved action catalog.
- Does not require a Photoshop plugin, Stream Deck plugin, helper application, external runtime, package dependency, or installer.
- Works offline and makes no network requests.

The canonical product terms are defined in [CONTEXT.md](../CONTEXT.md).

## Platform and product identity

- Product name: Action Script Picker
- Bundle identifier: `com.austinpresley.ActionScriptPicker`
- Version: `1.1.0`
- Build: `1`
- Copyright: `Copyright © 2026 Austin Presley`
- License: MIT
- Minimum system: macOS 13
- Architectures: Apple Silicon and Intel through one Universal application bundle
- Language: English in version 1, with user-facing strings kept ready for later localization

The app is a normal Dock application with one window. Closing the window leaves the app running. Reopening the app or choosing Show Window focuses the existing window. Command-Q quits. The app does not launch at login.

## Photoshop compatibility

Photoshop 2026, the 27.x family, is the tested target for version 1.

The app may offer another Photoshop release when it identifies as Adobe Photoshop and exposes the required `do javascript` and `do action` AppleScript commands. Such targets receive a quiet `Untested` label. They are compatible candidates, not claimed as physically verified releases.

Photoshop Beta appears in the target picker with a clear Beta label. A stable release always wins the automatic default. Beta becomes the default only when no stable installation exists.

## Target discovery

On each launch and refresh, the app discovers Photoshop application bundles under:

- `/Applications`
- `~/Applications`

The scan must find Photoshop when Adobe nests the application inside a version-named folder. It must not descend into unrelated application bundles.

`Choose Photoshop…` lets the user select an application stored elsewhere. A manually chosen path lasts only for the current app session.

The app remembers no target choice. Each launch selects the latest installed stable target, or the latest Beta when no stable target exists.

The latest target is chosen by:

1. Numeric release version.
2. Numeric build version.
3. The application path macOS resolves for the shared bundle identifier.
4. `/Applications` before `~/Applications`.
5. Canonical path as a deterministic final tie breaker.

Target-picker labels show application name and release version. They include Beta or Untested where applicable. The path appears when two entries would otherwise have the same label.

## Targeting generated scripts

The targeting rule is recorded in [ADR 0001](adr/0001-target-photoshop-by-verified-identity.md).

For the selected latest target, the app uses:

```applescript
tell application id "com.adobe.Photoshop"
```

This shared bundle identifier is the default even when Launch Services does not currently resolve it to the selected installation. Explicitly selected older, Beta, or version-specific targets use their absolute application path. Path-based targeting makes that version selection exact, but the copied script must be regenerated if the application moves.

The preview shows this note for a path-based script, outside the copyable source:

> This script targets this Photoshop installation. Regenerate it if the app moves.

## Generated AppleScript

The generated source has one purpose and no metadata or comments:

```applescript
tell application id "com.adobe.Photoshop"
    activate
    do action "AI SKIN CLEAN" from "BUILDING STATION"
end tell
```

Requirements:

- Four-space indentation.
- One trailing newline.
- Preview text and clipboard text match exactly.
- `activate` is always included.
- Action and action-set names retain exact case, whitespace, and Unicode content.
- Quotes, backslashes, tabs, line breaks, non-Latin text, and emoji produce valid AppleScript string expressions.
- Names are never normalized before script generation.

## Action data

Photoshop's live Actions panel is the sole source of action data.

- Action sets and actions retain Photoshop's panel order.
- Each action set displays a quiet action count.
- A complete successful response replaces the visible model atomically.
- A partial or malformed response fails the entire refresh.
- Action data lives in memory only and is never logged or written to disk.

The app queries Photoshop by sending inline JavaScript through Photoshop's built-in `do javascript` command. The query enumerates sets and actions by index and returns one JSON string. It includes a compatibility-safe JSON serializer instead of assuming that every older Photoshop JavaScript engine has the same built-in JSON support. The app does not create a temporary `.jsx` file.

AppleScript executes in the app process through native macOS scripting APIs. The app does not launch `/usr/bin/osascript` for queries.

## Ambiguous names

The app lists every action Photoshop returns, including duplicates, but it refuses to copy a script that cannot identify one action reliably.

An action reference is ambiguous when:

- Its action-set name is empty.
- Its action name is empty.
- Its action-set name appears more than once.
- Its action name appears more than once inside its uniquely named action set.

The same action name in two differently named sets is valid.

Ambiguous rows remain visible in panel order and show a warning. Copy Script is disabled. The message tells the user to rename the duplicate or empty item in Photoshop and Refresh. Empty values display as `Unnamed set` or `Unnamed action`, while the model retains the raw empty string.

## Selection and search

- After the first successful load, select the first action set and its first action when available.
- After refresh, preserve the selected set and action when their exact names still exist.
- Otherwise select the first available set and action.
- Selecting another set selects its first action immediately.
- An empty set remains selected, shows `No actions in this set`, clears the preview, and disables Copy Script.
- Search filters only the selected set's action names.
- Matching is a case-insensitive substring search.
- Changing sets clears the search.
- Search history is not retained.

## Window and controls

The window opens at about 900 by 560 points, resizes freely, and has a practical minimum of about 760 by 460 points. Standard macOS restoration remembers window size and position. No product selections are restored.

The main interface has:

- An action-set sidebar.
- A searchable action list.
- A read-only AppleScript preview.
- A left-side toolbar group with the target picker, Photoshop status, and Refresh.
- A Buy me a coffee link to `buymeacoffee.com/apresley` at the right of the toolbar.
- One Copy Script control below the preview.

At compact widths, the window title hides and Refresh remains icon-only. Scrolling content begins below the titlebar at every window size.

The preview uses selectable monospaced text, native system colors, and line wrapping. Version 1 has no syntax highlighting and no editable script state.

Copy Script changes to `Copied` briefly after a successful copy. It does not show an alert or notification.

Keyboard commands:

- Command-R: Refresh
- Command-F: Focus action search
- Shift-Command-C: Copy Script
- Command-C: Standard text copying in focused text controls

Menus include Show Window, Refresh, Focus Search, Copy Script, and the standard About, Hide, and Quit commands. Version 1 has no preferences window.

The interface uses native macOS controls, system light and dark appearances, standard spacing, system-defined contrast, full keyboard navigation, and descriptive VoiceOver labels. Color is never the sole status signal.

## Launching and observing Photoshop

When the selected target is already running, the utility queries it on launch. This first query may trigger the standard macOS Automation permission prompt.

When Photoshop is installed but closed, the utility does not launch it automatically. It shows an Open Photoshop button. Clicking that button launches the selected target without bringing it to the foreground, shows `Opening Photoshop…`, waits up to 60 seconds, and loads actions after Photoshop becomes ready.

Reading actions never activates Photoshop. The generated script activates Photoshop when the user later runs that script.

The utility observes application lifecycle notifications:

- When the selected target finishes launching outside the utility, load its actions.
- When the selected target quits, retain same-target results as stale, disable Copy Script, and update status immediately.

After the initial load, ordinary focus changes do not refresh actions. Refresh occurs only when the user invokes it. One Refresh operation rescans targets and reloads actions.

## Loading and timeouts

During a query, keep the current panes visible and responsive. Show progress in the toolbar. Temporarily disable target switching, Refresh, and Copy Script. Window movement, resizing, search, and text selection remain available.

- Photoshop launch timeout: 60 seconds
- Action-query timeout: 15 seconds

A timeout behaves like another query failure and offers Retry.

## Freshness and target switching

A failed refresh for the same target retains the last successful results as stale. Stale results remain visible for reference, but Copy Script is disabled.

If a different target fails to load, clear the prior target's results. Never display one Photoshop installation's actions as if they came from another installation.

## Status and errors

The toolbar status distinguishes at least:

- Photoshop missing
- Photoshop closed
- Opening Photoshop
- Loading actions
- Connected
- Stale results
- Automation permission required
- Timed out
- Query failed

Actionable errors appear inline in the relevant pane rather than in routine modal alerts.

Technical failures show a plain-language explanation and a collapsible Details section with the raw AppleScript or parsing error and a Copy Details command.

When Automation permission is denied, the app offers Open System Settings and Retry. It never requests or recommends Accessibility or Full Disk Access.

## Security and privacy

- App Sandbox: disabled
- Hardened Runtime: enabled
- Apple Events entitlement: enabled
- `NSAppleEventsUsageDescription`: included with a clear Photoshop-specific explanation
- Network access: none
- Telemetry and analytics: none
- Automatic update checks: none
- Crash reporting service: none
- Diagnostic file logs: none
- Persisted Photoshop content: none

## App icon

Version 1 includes a custom blue rounded-square macOS icon that combines an action-list motif with a script or play motif. It contains no text, Adobe `Ps` monogram, Adobe logo, or other trademarked artwork.

## Distribution

Version 1 is a self-contained local application that can be shared informally. It is not notarized and has no installer or updater.

Deliverables:

- Editable Xcode project and source.
- `Action Script Picker.app`.
- ZIP containing the same application bundle.
- README with build requirements, usage, permission recovery, compatibility, targeting behavior, verification steps, Gatekeeper limitations, license, and trademark notice.

The README must explain that an unnotarized downloaded build may trigger Gatekeeper. It may recommend the normal right-click Open route, but must not recommend disabling Gatekeeper or weakening macOS security.

The project states that Adobe Photoshop is a trademark of Adobe and that Action Script Picker is not affiliated with or endorsed by Adobe.

## Verification

Automated tests cover:

- Photoshop target discovery and filtering.
- Stable and Beta classification.
- Numeric release and build ordering.
- Latest-target tie breaking.
- Bundle-identifier versus path targeting.
- Query-response parsing and validation.
- Atomic refresh behavior.
- Selection preservation.
- Ambiguity detection.
- Search matching.
- AppleScript escaping for quotes, backslashes, tabs, line breaks, non-Latin text, and emoji.
- Exact preview and clipboard source formatting.

Photoshop is not installed on the development Mac. The build must not claim a live integration pass. The README includes a physical verification checklist for Photoshop 2026 covering discovery, Automation permission, action enumeration, special-character names, Refresh, version targeting, and execution of a copied script.
