#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Explicitly install, inspect, or remove the SN6140 Conexant module override.
# The vendor module is never overwritten.

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:-status}
kernel_release=$(uname -r)

# kernel_release becomes part of a privileged path for install/rollback.  Keep
# its accepted alphabet narrow before constructing that path.
[[ $kernel_release =~ ^[A-Za-z0-9._+-]+$ ]] || {
  printf 'ERROR: Unsafe kernel release string: %s\n' "$kernel_release" >&2
  exit 1
}

artifact="$project_dir/dist/$kernel_release/snd-hda-codec-conexant.ko.zst"
target_dir="/usr/lib/modules/$kernel_release/updates/sn6140"
target="$target_dir/snd-hda-codec-conexant.ko.zst"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: manage.sh [status|install|rollback]

status    Read-only comparison of the selected, loaded, and built modules.
install   Install an override under updates/sn6140 and run depmod. Requires root.
rollback  Remove only that override and run depmod. Requires root.

Neither install nor rollback unloads a live audio module. Reboot after either.
The distribution-owned module under kernel/sound/hda/codecs is never modified.
EOF
}

module_field() {
  local field=$1
  local file=$2
  modinfo -F "$field" "$file" 2>/dev/null || true
}

# Compare three different states: what depmod currently selects, what is already
# loaded in memory, and what this repository most recently built.
show_status() {
  local selected loaded_src built_src selected_src
  selected=$(modinfo -n snd_hda_codec_conexant 2>/dev/null || true)
  loaded_src=$(cat /sys/module/snd_hda_codec_conexant/srcversion 2>/dev/null || true)
  selected_src=$(module_field srcversion "${selected:-/nonexistent}")
  built_src=$(module_field srcversion "$artifact")

  printf 'kernel_release=%s\n' "$kernel_release"
  printf 'selected_module=%s\n' "${selected:-not-found}"
  printf 'override_file=%s\n' "$([[ -f $target ]] && echo present || echo absent)"
  printf 'loaded_srcversion=%s\n' "${loaded_src:-not-loaded}"
  printf 'selected_srcversion=%s\n' "${selected_src:-unknown}"
  printf 'built_srcversion=%s\n' "${built_src:-not-built}"

  if [[ -n $loaded_src && -n $built_src && $loaded_src == "$built_src" ]]; then
    printf 'active_override=yes\n'
  else
    printf 'active_override=no\n'
  fi
}

validate_artifact() {
  [[ -s $artifact ]] || die "Build artifact is missing: $artifact"
  [[ $(module_field name "$artifact") == snd_hda_codec_conexant ]] || \
    die 'Artifact has the wrong module name'

  local built_vermagic running_vermagic
  built_vermagic=$(module_field vermagic "$artifact")
  running_vermagic=$(modinfo -F vermagic snd_hda_codec_conexant 2>/dev/null || true)
  [[ -n $running_vermagic && $built_vermagic == "$running_vermagic" ]] || \
    die "Artifact vermagic does not match the running kernel"

  # The repository does not own an enrolled signing key.  Do not install an
  # artifact that the current kernel policy is guaranteed to reject.
  if [[ -r /sys/module/module/parameters/sig_enforce ]] &&
     [[ $(</sys/module/module/parameters/sig_enforce) == Y ]]; then
    die 'The running kernel enforces module signatures; this unsigned artifact cannot be installed safely'
  fi
  if [[ -r /sys/kernel/security/lockdown ]]; then
    local lockdown
    lockdown=$(</sys/kernel/security/lockdown)
    [[ $lockdown == *'[none]'* ]] || \
      die "Kernel lockdown is active: $lockdown"
  fi
}

case "$action" in
  status)
    show_status
    ;;
  install)
    ((EUID == 0)) || die 'install requires root; invoke this explicit action with sudo'
    if pacman -Qq sn6140-linux-zen-dkms >/dev/null 2>&1; then
      die 'The DKMS package is installed; manage this module with pacman, not the legacy installer'
    fi
    validate_artifact
    [[ ! -e $target ]] || die "Override already exists: $target"
    # updates/ has higher depmod priority than built-in module directories on
    # Arch.  Keeping the vendor file untouched makes rollback a one-file delete.
    install -Dm0644 "$artifact" "$target"
    depmod "$kernel_release"
    printf 'Installed override: %s\n' "$target"
    printf 'The vendor module was not overwritten. Reboot, then run: %s status\n' "$0"
    ;;
  rollback)
    ((EUID == 0)) || die 'rollback requires root; invoke this explicit action with sudo'
    if [[ -e $target ]]; then
      # This exact path is the only file the install action owns.
      rm -f -- "$target"
      rmdir --ignore-fail-on-non-empty "$target_dir" 2>/dev/null || true
      depmod "$kernel_release"
      printf 'Removed override: %s\n' "$target"
    else
      printf 'Override was already absent: %s\n' "$target"
    fi
    printf 'The distribution-owned module remains intact. Reboot to leave any loaded override.\n'
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
