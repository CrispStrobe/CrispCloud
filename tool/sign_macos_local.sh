#!/bin/bash
# Signs a locally built macOS release bundle so it runs on a registered Mac
# with its real identity (application identifier + team), which the
# data-protection system keychain requires. An ad-hoc signed bundle cannot use
# that keychain, so credential storage falls back to the startup error screen.
#
# Needs two MAC_APP_DEVELOPMENT profiles for this Mac, one for the app and one
# for the Finder extension, installed under
#   ~/Library/Developer/Xcode/UserData/Provisioning Profiles/
# and the matching "Apple Development" identity in a keychain on the search
# list. Profiles are looked up by name; override with APP_PROFILE/EXT_PROFILE.
#
# Usage: tool/sign_macos_local.sh [path/to/CrispCloud.app]
set -euo pipefail

APP="${1:-build/macos/Build/Products/Release/CrispCloud.app}"
TEAM="${TEAM:-N9XSJ4M3GT}"
BUNDLE_ID=com.CrispStrobe.cloud
EXT_BUNDLE_ID=com.CrispStrobe.cloud.FinderExtension
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -d "$APP" ] || { echo "No app bundle at $APP" >&2; exit 1; }

# find_profile <bundle id> -> newest macOS development profile for it
find_profile() {
  local want="$TEAM.$1" best="" best_exp=""
  for f in "$PROFILE_DIR"/*.provisionprofile; do
    [ -f "$f" ] || continue
    local plist="$WORK/p.plist"
    security cms -D -i "$f" > "$plist" 2>/dev/null || continue
    [ "$(/usr/libexec/PlistBuddy -c 'Print :Platform:0' "$plist" 2>/dev/null)" = OSX ] || continue
    /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$plist" >/dev/null 2>&1 || continue
    [ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$plist")" = "$want" ] || continue
    local exp
    exp=$(date -j -f '%a %b %d %T %Z %Y' "$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$plist")" +%s 2>/dev/null || echo 0)
    if [ -z "$best" ] || [ "$exp" -gt "$best_exp" ]; then best="$f"; best_exp="$exp"; fi
  done
  [ -n "$best" ] || { echo "No macOS development profile for $want in $PROFILE_DIR" >&2; return 1; }
  echo "$best"
}

APP_PROFILE="${APP_PROFILE:-$(find_profile "$BUNDLE_ID")}"
EXT_PROFILE="${EXT_PROFILE:-$(find_profile "$EXT_BUNDLE_ID")}"

# Sign with exactly the certificate the profile authorizes (by SHA-1), so an
# identically named identity in another keychain cannot make codesign ambiguous.
security cms -D -i "$APP_PROFILE" > "$WORK/app.plist"
/usr/libexec/PlistBuddy -c 'Print :DeveloperCertificates:0' "$WORK/app.plist" > "$WORK/cert.der"
IDENT=$(openssl x509 -inform DER -in "$WORK/cert.der" -noout -fingerprint -sha1 \
  | sed 's/.*=//; s/://g')
security find-identity -v -p codesigning | grep -q "$IDENT" \
  || { echo "Signing identity $IDENT from the profile is not in any keychain" >&2; exit 1; }

mkents() {  # mkents <source .entitlements> <bundle id> <out>
  cp "$1" "$3"
  /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$3" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$3" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM.$2" "$3"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM" "$3"
}

EXT="$APP/Contents/PlugIns/FinderExtension.appex"
cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
[ -d "$EXT" ] && cp "$EXT_PROFILE" "$EXT/Contents/embedded.provisionprofile"

# Nested first, same order and entitlements as .github/workflows/macos-release.yml.
HELPER="$APP/Contents/Resources/crispcloud_fuse_bridge"
if [ -x "$HELPER" ]; then
  codesign --force --sign "$IDENT" --entitlements macos/Runner/FuseBridge.entitlements "$HELPER"
fi
find "$APP/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0 2>/dev/null \
  | xargs -0 -I{} codesign --force --options runtime --sign "$IDENT" {}
find "$APP/Contents/Frameworks" -name '*.dylib' -print0 2>/dev/null \
  | xargs -0 -I{} codesign --force --options runtime --sign "$IDENT" {}
if [ -d "$EXT" ]; then
  mkents macos/FinderExtension/FinderExtension.entitlements "$EXT_BUNDLE_ID" "$WORK/ext.plist"
  codesign --force --options runtime --sign "$IDENT" --entitlements "$WORK/ext.plist" "$EXT"
fi
mkents macos/Runner/Release.entitlements "$BUNDLE_ID" "$WORK/app-ents.plist"
codesign --force --options runtime --sign "$IDENT" --entitlements "$WORK/app-ents.plist" "$APP"

codesign --verify --deep --strict "$APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "$TEAM.$BUNDLE_ID" \
  || { echo "application-identifier missing from the signed app" >&2; exit 1; }
echo "Signed $APP with $(security find-identity -v -p codesigning | grep "$IDENT" | sed 's/.*"\(.*\)"/\1/')"
