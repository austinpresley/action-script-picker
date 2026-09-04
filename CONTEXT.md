# Action Script Picker

Action Script Picker reads the actions loaded in a selected Adobe Photoshop installation and produces a copyable AppleScript for one action.

## Language

**Photoshop target**:
An installed Adobe Photoshop application selected as the source of loaded actions and the destination named by a generated script.
_Avoid_: Photoshop connection, Photoshop version when referring to the installed application rather than its release number

**Custom Photoshop target**:
A Photoshop target chosen from a nonstandard location for the current app session. The app does not remember it across launches.
_Avoid_: Saved target, custom version

**Latest Photoshop target**:
The stable Photoshop target with the newest release version, or the newest Beta target when no stable installation exists. This is the default target when more than one is installed.
_Avoid_: Current Photoshop, default Photoshop

**Compatible Photoshop target**:
A Photoshop target that exposes the AppleScript commands required to read loaded actions and run an action. Compatible targets may be offered even when their release has not been tested with Action Script Picker.
_Avoid_: Supported version, detected Photoshop

**Tested Photoshop target**:
A compatible Photoshop target whose complete read-and-generate flow has been verified. Photoshop 2026 is the only tested target for version 1.
_Avoid_: Guaranteed version, preferred version

**Loaded actions**:
The action sets and actions currently exposed by the selected Photoshop target's Actions panel.
_Avoid_: Action library, saved actions, installed actions

**Stale loaded actions**:
Loaded actions retained from the last successful query of the same Photoshop target after a later query fails. They may remain visible for reference but cannot produce a copyable script.
_Avoid_: Cached actions, offline actions

**Action set**:
A named container of actions in Photoshop's Actions panel.
_Avoid_: Folder, group, collection

**Action**:
A named Photoshop operation contained by an action set.
_Avoid_: Script, command

**Action reference**:
The exact action-set name and action name that together identify an action to Photoshop.
_Avoid_: Action name, action ID

**Ambiguous action reference**:
An action reference whose action-set name is duplicated, whose action name is duplicated within its uniquely named set, or whose action or set name is empty. It cannot identify one action reliably enough to copy.
_Avoid_: Duplicate action, invalid action

**Generated script**:
A standalone AppleScript that activates the selected Photoshop target and runs one action reference.
_Avoid_: Action, macro, snippet
