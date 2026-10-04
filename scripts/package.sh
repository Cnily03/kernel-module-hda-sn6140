#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Build a local Arch package, without installing packages or changing keyrings.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $# == 0 ]] || { echo 'Usage: package.sh (build only, no arguments)' >&2; exit 2; }
((EUID != 0)) || { echo 'Run package.sh as a normal user' >&2; exit 1; }
command -v makepkg >/dev/null || { echo 'Install Arch base-devel first' >&2; exit 1; }
mkdir -p "$project_dir/.work" "$project_dir/dist/packages" "$project_dir/cache/packages"
work=$(mktemp -d "$project_dir/.work/package.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
# Use a private config so user makepkg overrides cannot redirect build output
# or enable package signing. Package dependencies are checked, never installed.
cp /etc/makepkg.conf "$work/makepkg.conf"
printf '\nBUILDENV=(!distcc !color !ccache check !sign)\n' >> "$work/makepkg.conf"
mkdir -p "$work/tmp"
cd "$project_dir"
bsdtar -cf "$project_dir/cache/packages/sn6140-source.tar" \
  scripts/build.sh scripts/dkms-build.sh scripts/dkms-pre-install.sh \
  scripts/lib/detect.sh scripts/doctor.sh packaging/arch/dkms.conf module/Makefile \
  patches/0001-ALSA-hda-conexant-fix-Huawei-CREF-output-routing.patch
TMPDIR="$work/tmp" BUILDDIR="$work" SRCDEST="$project_dir/cache/packages" \
  PKGDEST="$project_dir/dist/packages" LOGDEST="$work" SRCPKGDEST="$work" \
  makepkg --config "$work/makepkg.conf" --cleanbuild --force
printf '\nPackage ready in %s/dist/packages/; nothing installed.\n' "$project_dir"
