#!/usr/bin/env bash
# linux/packaging/build_appimage.sh
#
# Creates an AppImage from the output of `flutter build linux --release`.
# Requires appimagetool to be in PATH (download from https://appimage.github.io/appimagetool/).
#
# Usage:
#   ./linux/packaging/build_appimage.sh [version]
#
# Outputs:
#   build/CrispCloud-<version>-x86_64.AppImage

set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="crispcloud"
DISPLAY_NAME="CrispCloud"

FLUTTER_BUILD_DIR="build/linux/x64/release/bundle"
APPDIR="build/AppDir"

echo "==> Building AppImage: ${DISPLAY_NAME}-${VERSION}-x86_64.AppImage"

# -----------------------------------------------------------------------
# 1. Verify dependencies
# -----------------------------------------------------------------------
if [ ! -d "${FLUTTER_BUILD_DIR}" ]; then
  echo "ERROR: Flutter build output not found at ${FLUTTER_BUILD_DIR}" >&2
  echo "       Run 'flutter build linux --release' first." >&2
  exit 1
fi

if ! command -v appimagetool >/dev/null 2>&1; then
  echo "ERROR: appimagetool not found in PATH." >&2
  echo "       Download from https://appimage.github.io/appimagetool/ and" >&2
  echo "       place it in /usr/local/bin or ~/.local/bin." >&2
  exit 1
fi

# -----------------------------------------------------------------------
# 2. Assemble AppDir structure
# -----------------------------------------------------------------------
rm -rf "${APPDIR}"
install -dm755 "${APPDIR}/usr/bin"
install -dm755 "${APPDIR}/usr/lib/${APP_NAME}"
install -dm755 "${APPDIR}/usr/share/applications"
install -dm755 "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# Copy flutter bundle.
cp -r "${FLUTTER_BUILD_DIR}/." "${APPDIR}/usr/lib/${APP_NAME}/"

# Wrapper script.
cat > "${APPDIR}/usr/bin/${APP_NAME}" <<'WRAPPER'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
exec "${HERE}/../lib/crispcloud/crispcloud" "$@"
WRAPPER
chmod 755 "${APPDIR}/usr/bin/${APP_NAME}"

# AppRun entry point required by AppImage spec.
cat > "${APPDIR}/AppRun" <<APPRUN
#!/usr/bin/env bash
exec "\${APPDIR}/usr/bin/${APP_NAME}" "\$@"
APPRUN
chmod 755 "${APPDIR}/AppRun"

# -----------------------------------------------------------------------
# 3. Desktop file + icon
# -----------------------------------------------------------------------
cp "linux/packaging/crispcloud.desktop" \
   "${APPDIR}/${APP_NAME}.desktop"
cp "linux/packaging/crispcloud.desktop" \
   "${APPDIR}/usr/share/applications/${APP_NAME}.desktop"

if [ -f "assets/icons/icon_256.png" ]; then
  cp "assets/icons/icon_256.png" \
     "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
  cp "assets/icons/icon_256.png" \
     "${APPDIR}/${APP_NAME}.png"
fi

# -----------------------------------------------------------------------
# 4. Build AppImage
# -----------------------------------------------------------------------
mkdir -p build
ARCH=x86_64 appimagetool \
  --comp gzip \
  "${APPDIR}" \
  "build/${DISPLAY_NAME}-${VERSION}-x86_64.AppImage"

echo ""
echo "==> AppImage built: build/${DISPLAY_NAME}-${VERSION}-x86_64.AppImage"
echo "    Make executable: chmod +x build/${DISPLAY_NAME}-${VERSION}-x86_64.AppImage"
echo "    Run with:        ./build/${DISPLAY_NAME}-${VERSION}-x86_64.AppImage"
