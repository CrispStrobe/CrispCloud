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

1. **Export compliance.** `Info.plist` currently says
   `ITSAppUsesNonExemptEncryption = false`. The app implements more than HTTPS:
   SSH, symmetric file encryption and VeraCrypt-compatible containers. Review
   whether the mass-market/standard-algorithm exemption applies. If it does not,
   set the key to `true` and file the required self-classification or CCATS
   documentation in App Store Connect. Do not leave it false merely to avoid the
   prompt.
2. **Process-based helpers outside the guarded features.** Search for
   `Process.run` / `Process.start` before each submission. The remaining uses
   include `df` for free space, `ln` for hard links, `id`/`stat` for ownership
   checks and `open -R` to reveal a file in Finder. They may work in the
   sandbox, but the App Store-safe replacements are, respectively, `statfs`,
   a POSIX `link(2)` FFI call, `FileStat`/FFI and `NSWorkspace`
   (`activateFileViewerSelecting`). Replace them if review or a sandbox test
   reports failures.
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
