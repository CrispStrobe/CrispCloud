
# CrispCloud

**CrispCloud** is an (unofficial) cross-platform Flutter client for secure cloud storage services, supporting **Filen.io**, **Internxt**, **WebDAV**, and **SFTP** (Secure File Transfer Protocol).

This client provides a **two-panel Commander-style interface** for managing your local files and your remote cloud drive side-by-side, focusing on speed, efficiency, privacy, and batch operations.

It runs natively on Desktop and Mobile, and as a **Progressive Web App (PWA)** directly in your browser.

## ⚠️ Disclaimer

This is an unofficial, open-source project and is **not** affiliated with, endorsed by, or supported by Filen.io, Internxt, or any other storage provider. It is a personal project built for learning and to provide an alternative interface. It is a work in progress. Use it at your own risk.

## Features

* **Provider Support:**
    * **Filen.io:** End-to-end encrypted Upload, Download, and file management. (Web version uses WebCrypto API for higher performance).
    * **Internxt:** Decentralized, encrypted cloud storage support.
    * **WebDAV:** Standard operations (Requires CORS support on Web).
    * **SFTP:** Support for standard SFTP connections (Requires WebSocket proxy on Web).
* **Cross-Platform:** Runs on **Web (PWA)**, **macOS**, **Windows**, **Linux**, **Android**, and **iOS**.
* **Two-Panel View:** Efficient "Commander" interface for moving files between Local and Remote.
* **Web Virtual File System:**
    * On the Web, the "Local" pane acts as a **Virtual Staging Area**.
    * Supports picking entire folders (Chrome/Edge) via the File System Access API.
    * In-memory processing for "Save As" downloads.
* **MacOS Security Scoped Bookmarks:** Support for macOS App Sandbox permissions. The app remembers granted folder access across restarts.
* **Resumable Operations:** Auto-login and state restoration for seamless sessions.
* **Batch Operations:**
    * **Recursive Upload/Download:** Transfer entire folder structures.
    * **Queuing:** Manage multiple transfers with a progress panel.
    * **Conflict Resolution:** Options to skip, overwrite, or rename files.
* **File Management:** Create folders, Rename, Move, Copy, and Delete (Trash/Permanent).
* **Search & Find:**
    * **Deep Search:** Recursively find files within the cloud drive.
    * **Pattern Matching:** Supports glob patterns (e.g., `*.pdf`).
* **Keyboard Centric:** Fully navigable via keyboard shortcuts.

## 🌍 Important: How it works on Web

The Web version (Demo available at [crisp-cloud.vercel.app](https://crisp-cloud.vercel.app/)) runs entirely in your browser sandbox, which introduces a unique workflow compared to desktop apps:

### 1. The "Local" Pane is Virtual

Browsers do not have direct access to your computer's file system (C:\ or /Home).

* To see files in the **Left (Local) Pane**, you must click **Open Local Folder**.
* **Important:** Your browser might label this action as "Upload" or asking to "Upload" the directory. **This does not upload your files to the cloud.**
* It simply grants the web app permission to *read* the file metadata (names, sizes) and "mount" that folder into the web app's memory.
* Actual upload to the cloud only happens when you explicitly select files and click **Copy/Upload** to the Right (Remote) Pane.

### 2. Browser Security Constraints

* **Save/Download:** When downloading files *from* the cloud, some modern browsers (Chrome/Edge) allow saving directly to your mounted folder. Older browsers or Safari may default to your standard "Downloads" folder.
* **WebDAV/SFTP:** Your servers must support **CORS** (Cross-Origin Resource Sharing) or use a WebSocket proxy (for SFTP) to allow connections from a browser.

## Getting Started

### Prerequisites

* [Flutter SDK](https://flutter.dev/docs/get-started/install) (>=3.0.0)
* A Filen.io or Internxt account, or credentials for an SFTP or WebDAV server.

### Installation

1. **Clone the repository:**
```bash
git clone https://github.com/CrispStrobe/cloud-dart.git
cd cloud-dart

```


2. **Get dependencies:**
```bash
flutter pub get

```


3. **Run the app:**
Select your target device and run:
```bash
# For Web (Chrome)
flutter run -d chrome --release

# For macOS
flutter run -d macos

# For Windows
flutter run -d windows

```



## Keyboard Shortcuts

The interface is designed for speed. Use these keys to navigate:

| Key | Action |
| --- | --- |
| `Tab` | Switch between Local and Remote panels |
| `Enter` | Open selected folder |
| `Backspace` | Navigate to parent folder |
| `Ctrl`/`Cmd` + `A` | Select all files in the active panel |
| `Escape` | Clear selection in the active panel |
| `Delete` | Delete selected items |
| `F2` | Rename selected item |
| `Ctrl`/`Cmd` + `N` | Create a new folder |
| `Ctrl`/`Cmd` + `R` / `F5` | Refresh the active panel |
| `Ctrl`/`Cmd` + `C` | Copy selected items (Local only) |
| `Ctrl`/`Cmd` + `X` | Move selected items |
| `Ctrl`/`Cmd` + `U` | Upload selected local items to remote |
| `Ctrl`/`Cmd` + `D` | Download selected remote items to local |

## Architecture

This project uses a modular Adapter pattern to abstract specific cloud provider APIs:

* **`CloudStorageClient`**: The abstract interface defining common operations (login, list, upload, download).
* **`FilenClientAdapter`**: Implementation using the Filen API (with WebCrypto optimization).
* **`InternxtClientAdapter`**: Implementation for Internxt decentralized storage.
* **`SFTPClientAdapter`**: Implementation using `dartssh2`. On Web, this uses a custom `WebSSHSocket` wrapper.
* **`WebDAVClientAdapter`**: Implementation using `webdav_client` for generic WebDAV support.
* **`LocalFileService`**: Abstracts file system access.
* **Desktop/Mobile:** Uses `dart:io` and platform-specific bookmarks (macOS Security Scope).
* **Web:** Uses a virtual in-memory file tree and `universal_html` / File System Access API.


### Known Limitations

* **Large Files (Web):** The current architecture reads files into memory (`Uint8List`) before uploading. This may cause crashes when uploading files larger than the available browser tab RAM (typically 2GB-4GB).

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0**. See the `LICENSE` file for details.

This app is not affiliated with Filen.io, Internxt, or any other cloud/storage provider. All trademarks and brand names belong to their respective owners.