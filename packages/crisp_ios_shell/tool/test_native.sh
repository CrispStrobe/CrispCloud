#!/bin/bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$PACKAGE_DIR/tool/prepare.py"
python3 -m unittest discover -s "$PACKAGE_DIR/tool/tests" -v

SIMULATOR_UDID="${1:-}"
if [[ -z "$SIMULATOR_UDID" ]]; then
  SIMULATOR_UDID="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
state = json.load(sys.stdin)
phones = [d for runtime, devices in state["devices"].items() if "iOS" in runtime for d in devices if d.get("isAvailable") and "iPhone" in d["name"]]
if not phones:
    raise SystemExit("No available iPhone simulator. Install an iOS runtime in Xcode first.")
phones.sort(key=lambda d: (d["state"] != "Booted", d["name"]), reverse=False)
print(phones[0]["udid"])
')"
fi
# 'boot' is idempotent from this script's point of view; bootstatus reports real failures.
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

SIM_ARCH="$(uname -m)"
SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TEST_DIR="$PACKAGE_DIR/.build/native-tests"
TEST_APP="$TEST_DIR/NativeShellTests.app"
mkdir -p "$TEST_APP/Frameworks"
python3 - "$PACKAGE_DIR" "$TEST_APP" "$SIM_ARCH" <<'PY'
import json, pathlib, plistlib, shutil, sys
package, app, arch = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
manifest = json.loads((package / 'tool/sources.json').read_text())
for name in manifest['targets'] + manifest['dash_variants']:
    xc = package / 'ios/Frameworks' / (name + '.xcframework')
    info = plistlib.loads((xc / 'Info.plist').read_bytes())
    choices = [v for v in info['AvailableLibraries'] if v.get('SupportedPlatform') == 'ios' and v.get('SupportedPlatformVariant') == 'simulator' and arch in v['SupportedArchitectures']]
    if len(choices) != 1:
        raise SystemExit(f'No unambiguous {arch} simulator slice for {name}')
    choice = choices[0]
    destination = app / 'Frameworks' / (name + '.framework')
    if destination.exists(): shutil.rmtree(destination)
    shutil.copytree(xc / choice['LibraryIdentifier'] / choice['LibraryPath'], destination, symlinks=True)
shutil.copy2(package / 'ios/Resources/commands.plist', app / 'commands.plist')
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'NativeShellTests', 'CFBundleIdentifier':'org.crispcloud.NativeShellTests', 'CFBundleName':'NativeShellTests', 'CFBundlePackageType':'APPL', 'CFBundleVersion':'1', 'CFBundleShortVersionString':'1.0', 'MinimumOSVersion':'15.0', 'CFBundleSupportedPlatforms':['iPhoneSimulator']}))
PY
xcrun --sdk iphonesimulator clang \
  -target "$SIM_ARCH-apple-ios15.0-simulator" -isysroot "$SIM_SDK" \
  -fobjc-arc -fblocks -Wall -Wextra -Werror=return-type \
  -I "$PACKAGE_DIR/ios/Classes" -F "$TEST_APP/Frameworks" \
  -framework ios_system -framework Foundation -framework UIKit \
  -Wl,-rpath,@executable_path/Frameworks -Wl,-export_dynamic \
  "$PACKAGE_DIR/ios/Classes/CISShellSession.m" \
  "$PACKAGE_DIR/ios/Classes/CISShellBridge.m" \
  "$PACKAGE_DIR/ios/Tests/NativeShellTests.m" \
  -o "$TEST_APP/NativeShellTests"

# Device compilation is mandatory too; simulator success cannot mask SDK/ABI issues.
DEVICE_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
DEVICE_FRAMEWORKS="$TEST_DIR/device-frameworks"
mkdir -p "$DEVICE_FRAMEWORKS"
python3 - "$PACKAGE_DIR" "$DEVICE_FRAMEWORKS" <<'PYDEVICE'
import pathlib, plistlib, shutil, sys
package, destination = map(pathlib.Path, sys.argv[1:])
xc = package / 'ios/Frameworks/ios_system.xcframework'
info = plistlib.loads((xc / 'Info.plist').read_bytes())
entry = next(v for v in info['AvailableLibraries'] if v['SupportedPlatform'] == 'ios' and not v.get('SupportedPlatformVariant') and 'arm64' in v['SupportedArchitectures'])
framework = destination / 'ios_system.framework'
if framework.exists(): shutil.rmtree(framework)
shutil.copytree(xc / entry['LibraryIdentifier'] / entry['LibraryPath'], framework, symlinks=True)
PYDEVICE
mkdir -p "$TEST_DIR/device"
for source in CISShellSession CISShellBridge; do
  xcrun --sdk iphoneos clang \
    -target arm64-apple-ios15.0 -isysroot "$DEVICE_SDK" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror=return-type \
    -I "$PACKAGE_DIR/ios/Classes" -F "$DEVICE_FRAMEWORKS" \
    -c "$PACKAGE_DIR/ios/Classes/$source.m" -o "$TEST_DIR/device/$source.o"
done
# Ad-hoc signing is sufficient for simulator execution; app store signing occurs
# in the parent Flutter app build when these frameworks are embedded.
for framework in "$TEST_APP"/Frameworks/*.framework; do
  codesign --force --sign - "$framework"
done
codesign --force --sign - "$TEST_APP"
python3 "$PACKAGE_DIR/tool/check_packaging.py" "$TEST_APP"
bash "$PACKAGE_DIR/tool/run_native_tests.sh" "$SIMULATOR_UDID" "$TEST_APP/NativeShellTests"
