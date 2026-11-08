# macOS App Store readiness

This is an entitlement and review audit for the macOS build. It is not a
substitute for an App Store Connect upload and review, but it separates the
things that are already correct from the features that need a Mac App Store
guard or a direct-download-only distribution path.

## Current entitlement set

`Runner/Release.entitlements` and `Runner/DebugProfile.entitlements` both keep
App Sandbox enabled and request only:

| Entitlement | Why it is there | App Store status |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | Required for Mac App Store | Correct |
| `com.apple.security.files.user-selected.read-write` | Folder/file picker and edits | Correct |
| `com.apple.security.files.bookmarks.app-scope` | Persist grants across launches | Correct |
| `com.apple.security.network.client` | Cloud, SSH and HTTPS connections | Correct |
| `com.apple.security.network.server` | In-app local WebDAV server | Allowed; keep the feature explicit in review notes |

`DebugProfile.entitlements` additionally has `com.apple.security.cs.allow-jit`.
That key is debug-only and must stay out of `Release.entitlements`.

The Finder Sync extension has its own sandbox and
`com.apple.security.files.user-selected.read-only`, which is the right minimum
for reading selected items. There is no application-group entitlement because
the extension hands work to the app through the `crispcloud://` URL scheme.

No `com.apple.security.temporary-exception.*`, no full-disk access, no Apple
Events/automation, no kernel-extension or system-extension entitlement and no
`com.apple.security.cs.disable-library-validation` are declared. Keep it that
way.

## Features that needed a Mac App Store guard

The App Store build cannot rely on a host process, a privileged helper or a
third-party kernel extension. The following are now disabled or replaced when a
Mac App Store receipt is present (`macos_app_store.dart`):

- **Local PTY terminal.** `Pty.spawn` uses `forkpty`/`tcsetattr`; App Sandbox
  denies the terminal-attribute call. The App Store build skips the PTY attempt
  and opens the built-in pure-Dart sandbox shell instead. The shell works on
  macOS, Linux, Windows, iOS, Android and the web and never launches a process.
  SSH remains the full remote-shell path.
- **macFUSE mounts.** macFUSE requires a kernel/system extension and a helper
  process. `FuseMountService.isSupported` is false in the App Store build, so
  the mount UI reports that mounts require the direct-download build.
- **VeraCrypt CLI integration.** The app does not bundle VeraCrypt; it invokes a
  separately installed privileged tool. That model is hidden in the App Store
  build.
- **Custom toolbar commands and automation `runCommand` actions.** These invoke
  user-configured executables. They are rejected in the App Store build.

These features remain available in a Developer ID (direct-download) build,
which is notarized but not sandboxed for the unsandboxed-only features.

## Privacy manifest

`macos/Runner/PrivacyInfo.xcprivacy` and
`macos/FinderExtension/PrivacyInfo.xcprivacy` declare:

- UserDefaults (`CA92.1`) for shared preferences.
- File timestamps (`DDA9.1`, `C617.1`) for file browsing, user-selected files and
  metadata.
- Disk space (`E174.1`) for free-space display.

Review this list whenever a plugin or feature starts using another
required-reason API (system boot time, active keyboards, pasteboard, etc.).
Plugin privacy manifests are copied by their own pod resources; the app-level
manifest covers CrispCloud's direct API use. `cryptography_flutter` 2.3.4 ships
its manifest inside `source_files` instead of a resource bundle, which produces
an Xcode "no rule to process file" warning and leaves the manifest out of the
framework. It is not on Apple's required-SDK list, so this is not a known
blocking issue; patch the podspec with a `resource_bundles` entry if App Store
Connect starts asking for it.

## Remaining review risks to verify before submission

1. **Export compliance (reviewed 2026-11-08).** The iOS and macOS source plists
   currently set `ITSAppUsesNonExemptEncryption=false` for the intended
   outside-France/no-documentation route. This is conditional: the
   [`apple-export-policy.json`](apple-export-policy.json)
   `prior_distribution_review` remains pending. Do not upload until the full
   inventory supports the actual Apple answers, the historical French-user
   and other-channel review is complete, live full App Store Connect
   availability confirms France is excluded, and the packaged app's plist
   matches the policy. Removing France from today's storefront does not stop
   updates to previous French customers. Filen, Internxt, vaults and bundled
   archive/document crypto make an OS-only or HTTPS-only description incorrect;
   the inventory also includes published legacy algorithms, so do not claim
   they are all internationally standardized. A qualifying finished mass-market
   app can still avoid an annual BIS self-classification report and CCATS; that
   does not determine Apple's answer or French obligations. A France-enabled
   release needs the applicable French process and Apple's documentation route;
   a `true` answer must match its Apple-issued code and approved declaration.
   See [the export decision, upload requirements and official sources](export-compliance.md).
   Preserve the source, resolved dependencies, exact artifact hashes and release
   evidence. Source checks and a historical HTTP 409 do not establish live
   distribution, classification approval or readiness of the current binary.
2. **Process-based helpers.** Normal file operations no longer shell out:
   free space uses `statfs`/`GetDiskFreeSpaceEx`, hard links use `link(2)`,
   owner/mode checks use libc `stat`/`getuid`/`chmod`, Windows drives are
   probed directly, and reveal-in-file-manager opens the containing folder
   through `url_launcher`. Remaining subprocesses are the features that are
   themselves external-tool integrations: the FUSE helper/rclone and unmount
   tools, the VeraCrypt CLI, user-defined toolbar/automation commands, and the
   Windows Explorer registry integration. The first three are already disabled
   in the Mac App Store build; the registry path is replaced with Win32 APIs.
   Audit with:
   `grep -rn "Process\.\(run\|start\|runSync\)" lib`.
3. **Local WebDAV server.** `com.apple.security.network.server` is allowed, but
   explain the user-initiated local server in the review notes. If the server is
   not needed on macOS, removing the entitlement and the feature is the
   simplest review path.
4. **Finder Sync extension.** Verify the app and extension versions match, both
   bundles are sandboxed, and the extension is embedded with the standard
   “Embed App Extensions” phase. The extension must not be used to bypass the
   app's own sandbox.
5. **Notarization and hardened runtime.** The App Store build does not need the
   Developer ID notarization flow, but the direct-download build does. Use
   hardened runtime there, sign the Finder extension with the same team, and
   notarize the whole app bundle.
6. **No downloaded executable code.** The app downloads documents, images,
   archives and media, not code. The built-in shell and all language/runtime
   code are bundled. Keep it that way; App Store guideline 2.5.2 is about
   introducing executable functionality after review.

## Checks to run before upload

```sh
# Entitlements actually embedded in the signed app:
codesign -d --entitlements :- build/macos/Build/Products/Release/CrispCloud.app

# Privacy manifest syntax and project file syntax:
plutil -lint macos/Runner/PrivacyInfo.xcprivacy
plutil -lint macos/FinderExtension/PrivacyInfo.xcprivacy
plutil -lint macos/Runner.xcodeproj/project.pbxproj

# Sandbox-only smoke test: launch the signed app and confirm:
#   - Terminal opens the built-in shell, not a PTY error.
#   - Mount dialog says FUSE is unavailable in the App Store build.
#   - VeraCrypt actions are hidden/disabled.
#   - Folder grants and security-scoped bookmarks survive relaunch.

# Direct-download build only:
xcrun notarytool submit ... --wait
spctl --assess --type execute --verbose=4 CrispCloud.app
```
