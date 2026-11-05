# Extensions

CrispCloud has two extension mechanisms. Declarative command extensions describe
programs already installed on the user's computer. Trusted first-party Dart
plugins are compiled into the application and use the lifecycle registry.

## Command extension manifests

Open **Settings → Extensions → Import manifest**, paste or load a JSON file,
then choose **Review extension**. The review displays every executable,
argument, working-directory rule, timeout and requested menu/toolbar capability.
**Install disabled** saves the manifest; enable it separately in the manager.
Updating an existing ID requires **Replace disabled**, which clears previous
command overrides and disables the replacement until it is enabled again.

The actual panel command bar displays configured custom commands and enabled
toolbar extension actions. It is hidden when there are no applicable actions.
Context menu actions use the exact clicked rows, independently of a different
marked selection. Both hosts require verified local sources; cloud and unresolved
collection paths are not passed to native processes or path-only plugin hooks.
Each command opens an argument review and requires **Run**. **Command settings**
edits the actual executable, arguments, working directory and timeout used by
later actions. The manager also exports, resets and removes installed manifests.

A manifest contains metadata, explicit `toolbar` and/or `contextMenu`
capabilities, and 1–32 commands. Each command has an executable and an argument
array. Filenames expand into individual arguments through the custom-command
runner; they are never assembled into a shell command. `{SELECTED}` occupies a
whole argument and expands to one argument per selected file.

```json
{
  "format": "crispcloud.command-extension",
  "schemaVersion": 1,
  "id": "com.example.inspect",
  "name": "File inspector",
  "version": "1.0.0",
  "description": "Inspect selected local files with an installed program.",
  "capabilities": ["toolbar", "contextMenu"],
  "commands": [
    {
      "id": "inspect",
      "label": "Inspect files",
      "executable": "/usr/local/bin/file-inspector",
      "arguments": ["--", "{SELECTED}"],
      "useCurrentPanelPath": true,
      "timeoutSeconds": 300
    }
  ]
}
```

Use an absolute installed executable path or a program found on PATH. A relative
executable such as `./tool` is rejected. The argument separator `--`, where the
chosen program supports it, prevents filenames beginning with a dash from being
interpreted as its options.

Installation and replacement are inert: each starts disabled and runs no program
or initialization hook. Enabling exposes only the declared actions. Per-command
settings replace the executable, arguments, working directory and timeout through
the same validated command model. Export includes the effective configuration by
default. Settings and enabled state are persisted before they become active.
Disabling, reconfiguring, replacing or removing an extension invalidates already
captured actions, including an open review waiting for the user to press Run.

Manifests cannot install native or Dart binaries, background hooks, automatic
installation scripts, provider plugins or shell command strings. No executable
is downloaded. Supported placeholders are subject to the custom-command runner's
local-source verification and interpreter restrictions. Native processes use
bounded output, cancellation and a timeout; process execution is unavailable on
web.

Manifest limits are 1 MiB and 32 commands. The installed configuration is capped
at 128 extensions and 4 MiB. Malformed saved data remains intact and exposes an
error rather than being silently replaced with an empty configuration.

## First-party plugin lifecycle

`PluginRegistry` is owned by a provider instance. Register trusted plugin objects,
then await `initializeAll`. Initialization reads persisted enabled state and
settings before calling any plugin hook. Repeated or concurrent initialization
does not initialize a ready plugin again. Contributions are visible only after a
successful initialization and only for declared capabilities.

Disabling disposes the initialized instance and releases its scoped temporary
workspace. Re-enabling creates a fresh context and initializes again. A failed
initialization releases partial resources, retains a visible error, and remains
excluded until an explicit retry or re-enable. Saving settings persists them,
disposes the active context and reinitializes with the new values. Disabled
plugins remain disabled when their settings change. Registration IDs are
validated before any directory is created.

The native context owns an actual unique temporary directory that is removed
on disposal; web uses a virtual memory namespace. Disposed context methods reject
later use. The context is a scoped convenience API, **not an OS sandbox**:
first-party Dart code compiled into CrispCloud has the application's privileges.

Compiled plugins expose an optional `PluginToolbarButton.onPressed` callback and
`PluginMenuItem.onSelected` callback. The legacy `onPressedKey` is kept for data
compatibility but is not an executable action. Toolbar and context-menu callbacks
receive immutable, verified local path lists. A captured callback is invalidated
when its plugin is disabled, unloaded or restarted after a settings change.
The manager shows initialization errors, retry, enable/disable, JSON settings
(for plugins declaring `settings`) and session unload. Unload removes the
registered object for the current session; the application controls which trusted
first-party plugins are registered at its next startup.
