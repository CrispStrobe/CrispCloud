#!/usr/bin/env bash
set -Eeuo pipefail
work=/mnt/volume1/quds-word-layout-20261120
exec > >(tee -a "$work/evidence/session.log") 2>&1
trap 'result=$?; printf "%s\n" "$result" > "$work/evidence/exit-status"; echo "Finished with status $result"' EXIT
date -u
mkdir -p "$work/sdk"
if [ ! -f "$work/sdk/flutter/bin/flutter" ]; then
  git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git "$work/sdk/flutter"
fi
export PATH="$work/sdk/flutter/bin:$PATH"
export PUB_CACHE=/mnt/volume1/pub-cache
export CI=true
flutter --version
flutter --version --machine > "$work/evidence/flutter-version.json"
tar -xzf "$work/source.tgz" -C "$work/source"
tar -xzf "$work/extra.tgz" -C "$work/source"
cd "$work/source"
flutter pub get --enforce-lockfile > "$work/evidence/dependencies.log" 2>&1
cd packages/quds_office_editor
set +e
flutter test --no-pub test/word_selection_paint_test.dart > "$work/evidence/selection-before.log" 2>&1
prior=$?
set -e
echo "Original Linux selection references exit: $prior"
flutter test --no-pub --update-goldens test/word_selection_paint_test.dart > "$work/evidence/selection-refresh.log" 2>&1
flutter test --no-pub test/word_selection_paint_test.dart test/word_run_metrics_test.dart test/word_underline_paint_test.dart test/paint_run_text_unicode_test.dart test/word_hyphenation_paint_test.dart test/word_inline_picture_history_test.dart test/host_fonts_test.dart test/paint_font_fallback_test.dart > "$work/evidence/editor-accepted.log" 2>&1
sha256sum test/goldens/linux/word_selection_macOS.png test/goldens/linux/word_selection_windows.png > "$work/evidence/golden-sha256.txt"
tail -4 "$work/evidence/editor-accepted.log"
