#!/bin/sh
# Install the complete relocatable CLI bundle, including native libraries.
set -eu
umask 077
prefix="$HOME/.local"
case "${1:-}" in
  --help|-h) echo 'Usage: sh install.sh [--prefix DIRECTORY]'; echo 'Installs crispcloud and its crisp compatibility command. Add DIRECTORY/bin to PATH.'; exit 0 ;;
  --prefix) [ "$#" = 2 ] || { echo 'Expected --prefix DIRECTORY' >&2; exit 2; }; prefix=$2 ;;
  '') ;;
  *) echo 'Usage: sh install.sh [--prefix DIRECTORY]' >&2; exit 2 ;;
esac
case "$prefix" in /*) ;; *) echo 'Installation prefix must be absolute.' >&2; exit 2 ;; esac
[ "$prefix" != / ] || { echo 'Use a user-local or dedicated installation prefix.' >&2; exit 2; }
bundle=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -x "$bundle/bin/crispcloud" ] && [ -x "$bundle/bin/crisp" ] || { echo 'Run the installer from an extracted, complete CLI bundle.' >&2; exit 1; }
managed="$prefix/lib/crispcloud"
[ ! -L "$managed" ] || { echo 'Refusing a symbolic-link installation directory.' >&2; exit 1; }
if [ -d "$managed" ] && [ ! -f "$managed/.crispcloud-managed" ]; then
  echo 'Refusing to replace an unmanaged installation directory.' >&2; exit 1
fi
for name in crispcloud crisp; do
  link="$prefix/bin/$name"
  if [ -e "$link" ] || [ -L "$link" ]; then
    [ -L "$link" ] && [ "$(readlink "$link")" = "$managed/current/bin/$name" ] || {
      echo "Refusing to replace an unrelated command: $link" >&2; exit 1;
    }
  fi
done
if [ -e "$managed/current" ] && [ ! -L "$managed/current" ]; then
  echo 'Refusing an unmanaged current installation.' >&2; exit 1
fi
mkdir -p "$prefix/bin" "$managed/releases"
printf '%s\n' 'CrispCloud CLI installation version 1' > "$managed/.crispcloud-managed"
stage=$(mktemp -d "$managed/releases/.install-XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' HUP INT TERM
cp -RP "$bundle/." "$stage/"
[ -x "$stage/bin/crispcloud" ] && [ -x "$stage/bin/crisp" ]
release="$managed/releases/release-$(date +%Y%m%d%H%M%S)-$$"
[ ! -e "$release" ] || { echo 'Installation release already exists.' >&2; exit 1; }
mv "$stage" "$release"
ln -sfn "$release" "$managed/current"
for name in crispcloud crisp; do
  [ -L "$prefix/bin/$name" ] || ln -s "$managed/current/bin/$name" "$prefix/bin/$name"
done
echo "Installed: $prefix/bin/crispcloud"
echo 'crisp is a compatibility command with the same capabilities.'
echo "Add $prefix/bin to PATH if needed. Previous releases are retained in $managed/releases."
