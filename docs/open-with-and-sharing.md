# Open with, receiving shares and sending shares

Files handed to CrispCloud by other apps all go through one Dart queue,
`ExternalOpenService` (`lib/services/external_open_service.dart`), consumed by
`ExternalOpenListener` (`lib/widgets/external_open_handler.dart`) once the file
browser is on screen.

| Request | Result |
|---|---|
| **Open with** / double-click on a registered type | The active pane moves to the file's folder with the file under the cursor and opens it in the normal viewer (F3), so editing, printing and copying work as usual. If only the file itself is readable (sandboxed macOS/iOS), the viewer opens it directly. |
| **Received share** | The files are copied to `<app support>/Received/<timestamp>/`, which the active pane shows with the files selected — copy them to any storage with F5. |
| **Reveal** (Finder/Explorer "Upload to CrispCloud") | The files are shown selected in their own folder. |

## Platforms

| Platform | Open with | Receive shares | Send shares |
|---|---|---|---|
| macOS | `CFBundleDocumentTypes` (rank *Alternate*: listed, never the default) + imported UTIs; `application(_:open:)` → `com.crispcloud/external_open` | Share extension (`macos/ShareExtension`) → App Group inbox → `crispcloud://received?id=…` | `share_plus` (NSSharingServicePicker) |
| iOS | `CFBundleDocumentTypes`; `scene(_:openURLContexts:)` copies the document to `tmp/Opened/` | Share extension (`ios/ShareExtension`, now built and embedded) → App Group inbox, delivered when the app becomes active | `share_plus` |
| Android | `VIEW` for `content:`/`file:` URIs | `SEND`/`SEND_MULTIPLE` via `receive_sharing_intent`; `MainActivity` reports which action it was | `share_plus` |
| Windows | Registered at every start under HKCU (`CrispCloud.Document` ProgID, `Applications\<exe>\SupportedTypes`, `.ext\OpenWithProgids`) — no default changes, no admin rights. A second launch forwards its files to the running window (`WM_COPYDATA`). | Not available: Share targets require an MSIX-packaged app; CrispCloud ships as a zip. | `share_plus` (Windows 10 1809+) |
| Linux | `MimeType=` in `linux/packaging/crispcloud.desktop`; single instance through GApplication (`command_line`), falling back to independent instances without a session bus | No system share target exists (the Nautilus script remains) | Not available: no system share sheet |

The Windows extension list is `externalOpenExtensions`; keep it, the Apple
content types and the Linux MIME types in step with the viewers
(`InternalViewerService`).

## Release signing

The share extensions have their own bundle ID,
`com.CrispStrobe.cloud.ShareExtension`, and ship in App Store builds only when
their profiles exist: `ASC_PROFILE_MACOS_SHAREEXT_BASE64` (macOS) and
`ASC_PROFILE_SHAREEXT_BASE64` (iOS, profile name
"CrispCloud ShareExtension AppStore CI"). Otherwise the workflows remove the
extension before signing. Developer ID signing embeds `SHARE_DEVID_PROFILE`
when set.
