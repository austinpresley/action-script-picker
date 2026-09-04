# Default to Photoshop's shared bundle identifier

Generated scripts use Photoshop's shared bundle identifier for the selected latest stable target. This is the default even when Launch Services does not currently resolve the identifier to that installation. Explicitly selected older, Beta, or version-specific targets use the selected application's absolute path.

This keeps the normal script resilient to Photoshop updates while preserving an exact installation choice when the user selects a non-default target.

## Consequences

The default script follows whichever stable Photoshop installation owns `com.adobe.Photoshop` when it runs. Path-targeted scripts are specific to one Mac and stop working if that Photoshop application moves. The preview shows a note for path-targeted scripts before the user copies one.
