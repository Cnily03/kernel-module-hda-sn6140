#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
source "$project_dir/scripts/lib/detect.sh"
[[ $# == 1 ]] || die 'Expected target kernel release'
check_legacy_override "$1"
detect_hardware
