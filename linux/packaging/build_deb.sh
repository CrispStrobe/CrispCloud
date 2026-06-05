#!/usr/bin/env bash
# linux/packaging/build_deb.sh
#
# Builds a .deb package from the output of `flutter build linux --release`.
#
# Usage:
#   ./linux/packaging/build_deb.sh [version]
#
# Outputs:
#   build/crisp_cloud_<version>_amd64.deb

set -euo pipefail

VERSION="${1:-1.0.0}"
ARCH="amd64"
PACKAGE_NAME="crisp-cloud"
APP_NAME="crispcloud"
DISPLAY_NAME="CrispCloud"
MAINTAINER="CrispCloud Team <support@crispcloud.app>"
DESCRIPTION="Cross-platform cloud file manager supporting 11 providers"
HOMEPAGE="https://crispcloud.app"

FLUTTER_BUILD_DIR="build/linux/x64/release/bundle"
DEB_ROOT="build/deb_pkg"
DEB_NAME="${PACKAGE_NAME}_${VERSION}_${ARCH}"

echo "==> Building .deb package: ${DEB_NAME}.deb"

# -----------------------------------------------------------------------
# 1. Verify flutter build output exists
# -----------------------------------------------------------------------
if [ ! -d "${FLUTTER_BUILD_DIR}" ]; then
  echo "ERROR: Flutter build output not found at ${FLUTTER_BUILD_DIR}" >&2
  echo "       Run 'flutter build linux --release' first." >&2
  exit 1
fi

# -----------------------------------------------------------------------
# 2. Create staging directory structure
# -----------------------------------------------------------------------
rm -rf "${DEB_ROOT}"
install -dm755 "${DEB_ROOT}/DEBIAN"
install -dm755 "${DEB_ROOT}/usr/bin"
install -dm755 "${DEB_ROOT}/usr/lib/${APP_NAME}"
install -dm755 "${DEB_ROOT}/usr/share/applications"
install -dm755 "${DEB_ROOT}/usr/share/icons/hicolor/256x256/apps"
install -dm755 "${DEB_ROOT}/usr/share/doc/${PACKAGE_NAME}"

# -----------------------------------------------------------------------
# 3. Copy binary + shared libraries + data
# -----------------------------------------------------------------------
cp -r "${FLUTTER_BUILD_DIR}/." "${DEB_ROOT}/usr/lib/${APP_NAME}/"

# Create wrapper script in /usr/bin so the binary is on PATH.
cat > "${DEB_ROOT}/usr/bin/${APP_NAME}" <<WRAPPER
#!/usr/bin/env bash
exec /usr/lib/${APP_NAME}/${APP_NAME} "\$@"
WRAPPER
chmod 755 "${DEB_ROOT}/usr/bin/${APP_NAME}"

# -----------------------------------------------------------------------
# 4. Desktop file + icon
# -----------------------------------------------------------------------
cp "linux/packaging/crispcloud.desktop" \
   "${DEB_ROOT}/usr/share/applications/${APP_NAME}.desktop"

if [ -f "assets/icons/icon_256.png" ]; then
  cp "assets/icons/icon_256.png" \
     "${DEB_ROOT}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi

# -----------------------------------------------------------------------
# 5. DEBIAN/control
# -----------------------------------------------------------------------
INSTALLED_SIZE=$(du -sk "${DEB_ROOT}/usr" | cut -f1)

cat > "${DEB_ROOT}/DEBIAN/control" <<CONTROL
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libblkid1, liblzma5
Section: net
Priority: optional
Homepage: ${HOMEPAGE}
Description: ${DESCRIPTION}
 CrispCloud supports Dropbox, Google Drive, OneDrive, Box, SFTP, S3,
 Backblaze B2, Filen, Internxt, WebDAV, and local storage. It provides
 file browsing, upload/download, sync, and search across all providers.
CONTROL

# -----------------------------------------------------------------------
# 6. DEBIAN/postinst — update MIME / desktop databases
# -----------------------------------------------------------------------
cat > "${DEB_ROOT}/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default crispcloud.desktop x-scheme-handler/crispcloud || true
fi
POSTINST
chmod 755 "${DEB_ROOT}/DEBIAN/postinst"

# -----------------------------------------------------------------------
# 7. Build the .deb
# -----------------------------------------------------------------------
mkdir -p build
dpkg-deb --build --root-owner-group "${DEB_ROOT}" "build/${DEB_NAME}.deb"

echo ""
echo "==> Package built: build/${DEB_NAME}.deb"
echo "    Install with:   sudo dpkg -i build/${DEB_NAME}.deb"
