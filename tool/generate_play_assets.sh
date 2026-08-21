#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"

cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)
if [ -r /proc/loadavg ]; then
  one_minute_load=$(awk '{print $1}' /proc/loadavg)
else
  one_minute_load=$(sysctl -n vm.loadavg | awk '{print $2}')
fi

if awk -v load="$one_minute_load" -v cpus="$cpu_count" \
  'BEGIN { exit !(load > cpus * 1.5) }'; then
  echo "Refusing Flutter asset render: load $one_minute_load on $cpu_count CPUs." >&2
  echo "Wait for load to fall below $((cpu_count * 3 / 2)) or set FORCE_STORE_ASSETS=1." >&2
  if [ "${FORCE_STORE_ASSETS:-0}" != "1" ]; then exit 1; fi
fi

echo "Rendering Play assets at load $one_minute_load on $cpu_count CPUs."
flutter test test/store_assets/store_assets_test.dart \
  --tags store-assets --run-skipped --update-goldens --concurrency=1

if command -v magick >/dev/null 2>&1; then
  for asset in store/google_play/assets/phone/*.png \
    store/google_play/assets/feature-graphic-1024x500.png; do
    temporary_asset="${asset%.png}.rgb.png"
    magick "$asset" -background white -alpha remove -alpha off \
      -define png:color-type=2 "$temporary_asset"
    mv "$temporary_asset" "$asset"
  done
else
  echo "ImageMagick is required to remove PNG alpha for Google Play." >&2
  exit 1
fi

echo "Google Play assets regenerated and converted to 24-bit PNG."
