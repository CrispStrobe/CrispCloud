# macOS Finder locations (File Provider)

CrispCloud can show a connected account under **Locations** in the Finder
sidebar (Mount as Drive → Finder sidebar → "Show current account in Finder").
This uses Apple's File Provider framework (`NSFileProviderReplicatedExtension`),
the same mechanism as the Dropbox, OneDrive and Google Drive desktop apps.

Unlike the macFUSE/FUSE-T mounts it needs no third-party runtime, kernel
extension or installer and stays inside the App Sandbox, so it is part of the
**Mac App Store** build as well as the GitHub build. (FUSE-T and macFUSE
remain GitHub-only: see [FUSE audit](fuse_and_license_audit.md).)

## How it works

- `macos/CrispCloudFileProvider/` is a sandboxed app extension. It cannot run
  the Dart provider adapters, so it forwards every operation to the running app.
- The app (`lib/services/finder_location_service.dart`) serves each location
  with the existing `FuseFilesystem` IPC protocol on a Unix socket at
  `<App Group container>/fp/<location id>`. The App Group
  `$(TeamIdentifierPrefix)crispcloud` is shared by the app and the extension.
- Identifiers are opaque and kept stable across renames by a per-location
  index in the extension's container. Remote changes are found by comparing
  folder listings; the app signals Finder every minute while serving.
- Uploads go through `create`/`write`/`release`; a failed copy is dropped with
  the `discard` opcode so a partial file is never uploaded.

## Limits

- Files open only while CrispCloud is running and connected to that account;
  otherwise Finder reports the location as unreachable. Locations are restored
  automatically when the account reconnects.
- Uploads are buffered by the app in memory and limited to 512 MiB per file.
- Dates, tags and other Finder metadata are kept locally, not on the provider.
- Remote changes appear after the next refresh (about a minute), or when a
  folder is reopened.

## Release signing

The extension's bundle ID is `com.CrispStrobe.cloud.FileProvider`. The App
Store workflow signs it when the `ASC_PROFILE_MACOS_FILEPROVIDER_BASE64` secret
holds its Mac App Store provisioning profile (App Groups capability with the
team-prefixed `crispcloud` group). Without that secret the workflow removes
the extension and ships the app without Finder locations.

## FSKit

Apple's FSKit was evaluated on 2026-11-21 (macOS 26.2) as an alternative.
A sandboxed app cannot mount a non-disk FSKit volume before macOS 27
(`FSClient.mountSingleVolume`, which needs `com.apple.developer.fskit.mount`).
The module entitlement `com.apple.developer.fskit.fsmodule` needs a
provisioning profile, and the user must enable the module in System Settings.
Apple DTS states FSKit is not yet ready for full network file systems. File
Provider is therefore the App Store path; FSKit is worth revisiting on macOS 27.
