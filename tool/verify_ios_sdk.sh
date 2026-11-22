#!/usr/bin/env bash
# Read the SDK and deployment target from the final IPA's Mach-O load command.
set -euo pipefail

if [[ $# != 1 ]]; then
  echo 'Usage: bash tool/verify_ios_sdk.sh PATH.ipa' >&2
  exit 2
fi

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
/usr/bin/unzip -p "$1" Payload/Runner.app/Runner > "$scratch/Runner"
build_info=$(/usr/bin/xcrun vtool -show-build "$scratch/Runner")
printf '%s\n' "$build_info"
if ! awk '
  $1 == "platform" { platforms++; ios = ($2 == "IOS") }
  $1 == "sdk" { sdks++; sdk = ($2 ~ /^[0-9]+([.][0-9]+)*$/ && $2 + 0 >= 27) }
  $1 == "minos" { targets++; target = ($2 ~ /^[0-9]+([.][0-9]+)*$/ && $2 + 0 >= 15) }
  END { exit !(platforms == 1 && ios && sdks == 1 && sdk && targets == 1 && target) }
' <<< "$build_info"; then
  echo 'Exported Runner must target iOS 15+ and be linked with the iOS 27 SDK or newer.' >&2
  exit 1
fi
