#!/usr/bin/env bash
# Reconstruct the prior genuine SDK and exact test locks without modifying
# either repository's production dependency declarations. Run with the folder
# containing quds_office_suite and CrispCloud as the first argument.
set -euo pipefail
task_workspace=$(cd "${1:?Pass the workspace containing both checkouts}" && pwd)
task_toolchain="$task_workspace/zotero-toolchain"
task_scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$task_toolchain/logs" "$task_toolchain/tmp" "$task_toolchain/config" "$task_toolchain/pub-cache"
if [[ ! -d "$task_toolchain/flutter-sdk/.git" ]]; then
  git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git "$task_toolchain/flutter-sdk"
fi
test "$(git -C "$task_toolchain/flutter-sdk" rev-parse HEAD)" = 737ba8f885dc774b53b442759999a312c9461e4e
python3 "$task_scripts/reconstruct-harnesses.py" --workspace "$task_workspace" --toolchain "$task_toolchain"
source "$task_toolchain/env.sh"
"$FLUTTER_ROOT/bin/flutter" --version --machine > "$task_toolchain/logs/flutter-version.log" 2>&1
(
  cd "$task_toolchain/harness/quds_office_engine"
  "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get --enforce-lockfile
) > "$task_toolchain/logs/engine-pub-get.log" 2>&1
for task_harness in quds_office_editor quds_office_studio; do
  (
    cd "$task_toolchain/harness/$task_harness"
    "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" pub get --enforce-lockfile
  ) > "$task_toolchain/logs/$task_harness-pub-get.log" 2>&1
done
(
  cd "$task_toolchain/crisp-host-harness"
  "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" pub get --enforce-lockfile
) > "$task_toolchain/logs/host-pub-get.log" 2>&1
python3 "$task_scripts/record-setup.py" --toolchain "$task_toolchain"
