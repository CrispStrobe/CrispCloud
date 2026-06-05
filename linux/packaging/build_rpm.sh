#!/usr/bin/env bash
# linux/packaging/build_rpm.sh
#
# Generates an RPM spec file and builds a .rpm package from the output of
# `flutter build linux --release`.  Requires rpmbuild (rpm-build package).
#
# Usage:
#   ./linux/packaging/build_rpm.sh [version] [release]
#
# Outputs:
#   ~/rpmbuild/RPMS/x86_64/crisp-cloud-<version>-<release>.x86_64.rpm

set -euo pipefail

VERSION="${1:-1.0.0}"
RELEASE="${2:-1}"
PACKAGE_NAME="crisp-cloud"
APP_NAME="crispcloud"
DISPLAY_NAME="CrispCloud"
MAINTAINER="CrispCloud Team <support@crispcloud.app>"
URL="https://crispcloud.app"
SUMMARY="Cross-platform cloud file manager"

FLUTTER_BUILD_DIR="$(pwd)/build/linux/x64/release/bundle"
RPMBUILD_ROOT="${HOME}/rpmbuild"
SPEC_FILE="${RPMBUILD_ROOT}/SPECS/${PACKAGE_NAME}.spec"

echo "==> Building RPM package: ${PACKAGE_NAME}-${VERSION}-${RELEASE}.x86_64.rpm"

# -----------------------------------------------------------------------
# 1. Verify flutter build output
# -----------------------------------------------------------------------
if [ ! -d "${FLUTTER_BUILD_DIR}" ]; then
  echo "ERROR: Flutter build output not found at ${FLUTTER_BUILD_DIR}" >&2
  echo "       Run 'flutter build linux --release' first." >&2
  exit 1
fi

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "ERROR: rpmbuild not found. Install with: sudo dnf install rpm-build" >&2
  exit 1
fi

# -----------------------------------------------------------------------
# 2. Set up rpmbuild directory tree
# -----------------------------------------------------------------------
mkdir -p "${RPMBUILD_ROOT}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# -----------------------------------------------------------------------
# 3. Stage files into BUILDROOT
# -----------------------------------------------------------------------
BUILDROOT="${RPMBUILD_ROOT}/BUILDROOT/${PACKAGE_NAME}-${VERSION}-${RELEASE}.x86_64"
rm -rf "${BUILDROOT}"
install -dm755 "${BUILDROOT}/usr/bin"
install -dm755 "${BUILDROOT}/usr/lib/${APP_NAME}"
install -dm755 "${BUILDROOT}/usr/share/applications"
install -dm755 "${BUILDROOT}/usr/share/icons/hicolor/256x256/apps"

cp -r "${FLUTTER_BUILD_DIR}/." "${BUILDROOT}/usr/lib/${APP_NAME}/"

cat > "${BUILDROOT}/usr/bin/${APP_NAME}" <<WRAPPER
#!/usr/bin/env bash
exec /usr/lib/${APP_NAME}/${APP_NAME} "\$@"
WRAPPER
chmod 755 "${BUILDROOT}/usr/bin/${APP_NAME}"

cp "linux/packaging/crispcloud.desktop" \
   "${BUILDROOT}/usr/share/applications/${APP_NAME}.desktop"

if [ -f "assets/icons/icon_256.png" ]; then
  cp "assets/icons/icon_256.png" \
     "${BUILDROOT}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi

# -----------------------------------------------------------------------
# 4. Generate spec file
# -----------------------------------------------------------------------
cat > "${SPEC_FILE}" <<SPEC
Name:           ${PACKAGE_NAME}
Version:        ${VERSION}
Release:        ${RELEASE}%{?dist}
Summary:        ${SUMMARY}
License:        Proprietary
URL:            ${URL}
BuildArch:      x86_64

Requires:       gtk3, libblkid, xz-libs

%description
${DISPLAY_NAME} is a cross-platform cloud file manager supporting 11 providers
including Dropbox, Google Drive, OneDrive, S3, SFTP, and more.

%install
cp -a %{_builddir}/../BUILDROOT/${PACKAGE_NAME}-${VERSION}-${RELEASE}.x86_64/. \
   %{buildroot}/

%files
/usr/bin/${APP_NAME}
/usr/lib/${APP_NAME}/
/usr/share/applications/${APP_NAME}.desktop
%{?icon_present:/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png}

%post
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database -q /usr/share/applications || true
fi

%changelog
* $(date +"%a %b %d %Y") ${MAINTAINER} - ${VERSION}-${RELEASE}
- Initial package release
SPEC

# -----------------------------------------------------------------------
# 5. Build the RPM
# -----------------------------------------------------------------------
rpmbuild -bb \
  --define "_topdir ${RPMBUILD_ROOT}" \
  --define "_builddir ${RPMBUILD_ROOT}/BUILD" \
  "${SPEC_FILE}"

RPM_PATH=$(find "${RPMBUILD_ROOT}/RPMS/x86_64" \
  -name "${PACKAGE_NAME}-${VERSION}*.rpm" | head -1)

echo ""
echo "==> RPM built: ${RPM_PATH}"
echo "    Install with:   sudo rpm -i ${RPM_PATH}"
echo "    Or:             sudo dnf install ${RPM_PATH}"
