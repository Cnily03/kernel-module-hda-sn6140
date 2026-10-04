#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $# == 1 ]] || { echo 'Usage: dkms-build.sh KERNEL_RELEASE' >&2; exit 2; }
# All downloads are authenticated again on every build. DKMS owns installation,
# signing, compression and depmod. This script only produces the ELF module.
args=()
if ((EUID == 0)); then
  args+=(--cache /var/cache/sn6140)
fi
"$project_dir/scripts/build.sh" --dkms-kernel "$1" "${args[@]}"
install -m644 "$project_dir/dist/$1/snd-hda-codec-conexant.ko" "$project_dir/snd-hda-codec-conexant.ko"
