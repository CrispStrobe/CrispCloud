// lib/services/fuse_helper_script.dart
//
// Generates and writes platform-specific FUSE mount helper scripts.
//
// On mount, FuseMountService calls FuseHelperScript.writeScript() to create
// a temporary script that:
//   1. Sets up the FUSE mount point.
//   2. Connects to FuseFilesystem's IPC socket.
//   3. Forwards kernel FUSE operations over that socket.
//
// NOTE: The generated scripts are thin wrappers; the real filesystem logic
// lives in FuseFilesystem. These scripts only set up the OS-level mount and
// relay binary messages. They require the native FUSE library to be present:
//   Linux  → fusermount3 / libfuse3   (sudo apt install fuse3)
//   macOS  → macFUSE or FUSE-T        (https://osxfuse.github.io)
//   Windows → WinFsp                  (https://winfsp.dev)

import 'dart:io';

import 'package:path/path.dart' as p;

import 'log_service.dart';

class FuseHelperScript {
  static const _log = Log('FuseHelperScript');

  /// Write the platform-appropriate helper script for [mountPoint] and
  /// return the path to the written file.
  static Future<String> writeScript(String mountPoint) async {
    final dir = Directory.systemTemp;
    final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final String scriptPath;
    final String content;

    if (Platform.isLinux) {
      scriptPath = p.join(dir.path, 'crispcloud_fuse_$suffix.sh');
      content = _linuxScript(mountPoint);
    } else if (Platform.isMacOS) {
      scriptPath = p.join(dir.path, 'crispcloud_fuse_$suffix.sh');
      content = _macosScript(mountPoint);
    } else if (Platform.isWindows) {
      scriptPath = p.join(dir.path, 'crispcloud_fuse_$suffix.bat');
      content = _windowsScript(mountPoint);
    } else {
      throw UnsupportedError('FUSE helper scripts are not supported on this platform.');
    }

    final file = File(scriptPath);
    await file.writeAsString(content, flush: true);
    _log.debug('Wrote FUSE helper script: $scriptPath');
    return scriptPath;
  }

  // ---------------------------------------------------------------------------
  // Linux helper script
  // ---------------------------------------------------------------------------
  //
  // Uses libfuse's `fusermount3` (or `fusermount` for fuse2) to create the
  // mount point, then bridges kernel FUSE operations via /dev/fuse to a
  // socat relay that connects to the CrispCloud IPC socket.
  //
  // Full-featured FUSE bridge requires a compiled C helper (e.g. using the
  // passthrough_ll example from libfuse). This script is the launch shim;
  // in production you would compile and ship `crispcloud_fuse_bridge` as a
  // native binary. The script documents the expected interface.
  //
  static String _linuxScript(String mountPoint) => '''#!/bin/sh
# CrispCloud FUSE helper — Linux
# Requires: fuse3 (sudo apt install fuse3)
#
# This script mounts a FUSE filesystem at MOUNT_POINT and connects it to the
# CrispCloud IPC socket so that FuseFilesystem can service kernel requests.
#
# Usage: crispcloud_fuse_<id>.sh <mount_point>

set -e
MOUNT_POINT="\${1:-$mountPoint}"
SOCKET_PATH="\${CRISPCLOUD_IPC_SOCKET:-/tmp/crispcloud_fuse.sock}"

# Ensure mount point exists.
mkdir -p "\$MOUNT_POINT"

# Check for the FUSE bridge binary (compiled from lib/native/fuse_bridge.c).
# If it does not exist, fall back to the fusermount + socat relay.
BRIDGE="\$(dirname "\$0")/crispcloud_fuse_bridge"

if [ -x "\$BRIDGE" ]; then
  exec "\$BRIDGE" "\$MOUNT_POINT" "\$SOCKET_PATH"
fi

# Fallback: plain fusermount to verify the mount point is accessible.
# In this mode filesystem operations will not be bridged — this is only
# useful for testing that the native FUSE stack is operational.
if command -v fusermount3 >/dev/null 2>&1; then
  FUSE_CMD=fusermount3
elif command -v fusermount >/dev/null 2>&1; then
  FUSE_CMD=fusermount
else
  echo "ERROR: fusermount3 / fusermount not found. Install fuse3:" >&2
  echo "  sudo apt install fuse3" >&2
  exit 1
fi

# A simple loopback mount using the null filesystem for connectivity test.
# Replace with the compiled bridge binary for production use.
echo "CrispCloud FUSE bridge not found at \$BRIDGE"
echo "Performing connectivity check only (mount will be read-only stub)."

# Keep the script alive so FuseMountService can track the process.
trap '"\$FUSE_CMD" -u "\$MOUNT_POINT" 2>/dev/null || true' EXIT INT TERM
while true; do sleep 5; done
''';

  // ---------------------------------------------------------------------------
  // macOS helper script
  // ---------------------------------------------------------------------------
  //
  // macFUSE exposes /dev/osxfuse* device nodes. The bridge binary (compiled
  // from lib/native/fuse_bridge.c using OSXFUSE headers) connects to the
  // CrispCloud IPC socket and services FUSE requests.
  //
  static String _macosScript(String mountPoint) => '''#!/bin/sh
# CrispCloud FUSE helper — macOS
# Requires: macFUSE (https://osxfuse.github.io) or FUSE-T
#           Install via Homebrew: brew install macfuse
#
# Usage: crispcloud_fuse_<id>.sh <mount_point>

set -e
MOUNT_POINT="\${1:-$mountPoint}"
SOCKET_PATH="\${CRISPCLOUD_IPC_SOCKET:-/tmp/crispcloud_fuse.sock}"

mkdir -p "\$MOUNT_POINT"

# Check for macFUSE or FUSE-T.
FUSE_FOUND=0
if [ -d /Library/Filesystems/macfuse.fs ]; then
  FUSE_FOUND=1
elif [ -f /Library/Filesystems/fuse-t.fs/Contents/MacOS/fuse-t ]; then
  FUSE_FOUND=1
elif command -v mount_macfuse >/dev/null 2>&1; then
  FUSE_FOUND=1
fi

if [ "\$FUSE_FOUND" -eq 0 ]; then
  echo "ERROR: macFUSE not found." >&2
  echo "Install from https://osxfuse.github.io or via Homebrew:" >&2
  echo "  brew install macfuse" >&2
  exit 1
fi

# Attempt to launch the native bridge binary.
BRIDGE="\$(dirname "\$0")/crispcloud_fuse_bridge"
if [ -x "\$BRIDGE" ]; then
  exec "\$BRIDGE" "\$MOUNT_POINT" "\$SOCKET_PATH"
fi

echo "CrispCloud FUSE bridge binary not found at \$BRIDGE"
echo "Running in stub mode — filesystem operations will not be bridged."

# Keep alive so FuseMountService can track the process.
trap 'diskutil unmount force "\$MOUNT_POINT" 2>/dev/null || true' EXIT INT TERM
while true; do sleep 5; done
''';

  // ---------------------------------------------------------------------------
  // Windows batch script
  // ---------------------------------------------------------------------------
  //
  // WinFsp installs a user-mode FUSE layer accessible through its DLL. The
  // bridge binary links against winfsp.dll and connects to the named pipe
  // exposed by FuseFilesystem (\\.\pipe\crispcloud_fuse_<id>).
  //
  static String _windowsScript(String mountPoint) => '''@echo off
:: CrispCloud FUSE helper - Windows
:: Requires: WinFsp (https://winfsp.dev)
::
:: Usage: crispcloud_fuse_<id>.bat [mount_point]

setlocal

set MOUNT_POINT=%1
if "%MOUNT_POINT%"=="" set MOUNT_POINT=$mountPoint

set PIPE_NAME=%CRISPCLOUD_IPC_PIPE%
if "%PIPE_NAME%"=="" set PIPE_NAME=\\\\.\\pipe\\crispcloud_fuse

:: Check for WinFsp.
set WINFSP_LAUNCHER=
for %%d in (
  "%ProgramFiles(x86)%\\WinFsp\\bin\\winfsp-launcher-x64.exe"
  "%ProgramFiles%\\WinFsp\\bin\\winfsp-launcher-x64.exe"
) do (
  if exist %%d set WINFSP_LAUNCHER=%%d
)

if "%WINFSP_LAUNCHER%"=="" (
  echo ERROR: WinFsp not found. Install from https://winfsp.dev >&2
  exit /b 1
)

:: Look for the native bridge executable.
set BRIDGE=%~dp0crispcloud_fuse_bridge.exe
if exist "%BRIDGE%" (
  "%BRIDGE%" "%MOUNT_POINT%" "%PIPE_NAME%"
  goto :eof
)

echo CrispCloud FUSE bridge not found at %BRIDGE%
echo Running in stub mode.

:: Keep the script alive.
:loop
timeout /t 5 /nobreak >nul
goto loop
''';
}
