#!/usr/bin/env bash
# Repackage an official upstream fnm prebuilt release binary into a .deb.
#
# Usage: build-deb.sh <version> <arch> [package_revision]
#   <version>           upstream tag, e.g. v1.39.0
#   <arch>              amd64 | arm64
#   [package_revision]  our packaging revision for this upstream version
#                        (Debian "debian_revision" convention). Defaults to 1.
#                        Bump this to publish a new .deb for the same
#                        upstream fnm version, e.g. after a packaging-only
#                        fix, without waiting for a new upstream release.

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <version> <arch> [package_revision]" >&2
  exit 1
fi

version="$1"
arch="$2"
package_revision="${3:-1}"

# Image used only to run dpkg-deb so package building is reproducible
# regardless of host OS (this script is expected to work from macOS too).
# No --platform flag is needed anywhere in this script: dpkg-deb --build
# never executes the packaged binary, it only archives files, so the
# container's own native platform is irrelevant to the target arch.
build_image="${BUILD_IMAGE:-debian:13}"

case "$arch" in
  amd64) asset="fnm-linux.zip" ;;
  arm64) asset="fnm-arm64.zip" ;;
  *)
    echo "Unsupported arch: $arch (expected amd64 or arm64)" >&2
    exit 1
    ;;
esac

version_number="${version#v}"
deb_version="${version_number}-${package_revision}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/dist"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

url="https://github.com/Schniz/fnm/releases/download/${version}/${asset}"

echo "Downloading ${url}"
curl -fL --retry 3 -o "$work_dir/$asset" "$url"

echo "Extracting ${asset}"
unzip -q "$work_dir/$asset" -d "$work_dir/extracted"

binary="$work_dir/extracted/fnm"
if [[ ! -f "$binary" ]]; then
  echo "Expected a single 'fnm' binary at the root of ${asset}, not found" >&2
  exit 1
fi

# Defensive linkage check: the whole point of shipping no Depends: field is
# that upstream's Linux releases are static-pie musl builds with zero
# runtime library dependencies. If a future fnm release changes how it's
# linked, this check catches it immediately instead of silently shipping a
# .deb that's missing a Depends: line it actually needs. Runs locally
# against the extracted binary -- no Docker/QEMU needed since it doesn't
# execute the binary, just inspects its ELF header.
link_info="$(file -b "$binary")"
if ! grep -qE 'static-pie linked|statically linked' <<<"$link_info"; then
  echo "ERROR: expected a statically linked binary, got: $link_info" >&2
  echo "fnm's linkage appears to have changed upstream -- this package" >&2
  echo "currently ships no Depends: field on the assumption of zero" >&2
  echo "runtime library dependencies. Reintroduce dependency detection" >&2
  echo "(see codexscribo/neovim-deb's ldd-based approach) before proceeding." >&2
  exit 1
fi

echo "Building package root"
pkgroot="$work_dir/pkgroot"
mkdir -p "$pkgroot/usr/bin" "$pkgroot/DEBIAN"
cp "$binary" "$pkgroot/usr/bin/fnm"
chmod 755 "$pkgroot/usr/bin/fnm"

doc_dir="$pkgroot/usr/share/doc/fnm"
mkdir -p "$doc_dir"
cp "$repo_root/debian/copyright" "$doc_dir/copyright"

changelog="$work_dir/changelog.Debian"
sed -e "s/__VERSION__/${deb_version}/g" \
    -e "s/__UPSTREAM_TAG__/${version}/g" \
    -e "s/__ARCH__/${arch}/g" \
    -e "s/__DATE__/$(date -R)/g" \
    "$repo_root/debian/changelog.template" > "$changelog"
gzip -9n -c "$changelog" > "$doc_dir/changelog.Debian.gz"

installed_size="$(du -sk "$pkgroot/usr" | cut -f1)"

echo "Writing control file"
sed -e "s/__VERSION__/${deb_version}/g" \
    -e "s/__ARCH__/${arch}/g" \
    -e "s/__INSTALLED_SIZE__/${installed_size}/g" \
    "$repo_root/debian/control.template" > "$pkgroot/DEBIAN/control"

deb_name="fnm_${deb_version}_${arch}.deb"
pkgroot_container="/work/pkgroot"

echo "Building ${deb_name} inside ${build_image}"
docker run --rm \
  -v "$work_dir:/work" \
  "$build_image" \
  dpkg-deb --root-owner-group --build "$pkgroot_container" "/work/${deb_name}"

mkdir -p "$dist_dir"
deb_path="$dist_dir/$deb_name"
cp "$work_dir/$deb_name" "$deb_path"

echo "Done: ${deb_path}"
