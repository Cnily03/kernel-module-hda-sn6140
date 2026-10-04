#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
script_dir=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
source "$script_dir/lib/detect.sh"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
action=${1:-check}
[[ $# -le 1 ]] || die 'Usage: sn6140 [check|status]'
case $action in
  check|status) ;;
  -h|--help) echo 'Usage: sn6140 [check|status] (read-only; never installs or loads modules)'; exit 0 ;;
  *) die 'Usage: sn6140 [check|status]' ;;
esac
for cmd in pacman modinfo; do command -v "$cmd" >/dev/null || die "Missing command: $cmd"; done
printf 'Running kernel: %s\n' "$(uname -r)"
detect_installed_kernel
printf 'Installed linux-zen target: %s\n' "$detected_kernel_release"
if [[ $(uname -r) != "$detected_kernel_release" ]]; then
  printf 'The installed kernel differs from the running kernel; DKMS builds for the installed target before reboot.\n'
fi
if command -v dkms >/dev/null; then
  dkms status -m sn6140
else
  warn 'dkms is not installed'
fi
selected=$(modinfo -n snd_hda_codec_conexant 2>/dev/null || true)
loaded_src=$(cat /sys/module/snd_hda_codec_conexant/srcversion 2>/dev/null || true)
selected_src=$(modinfo -F srcversion "${selected:-/nonexistent}" 2>/dev/null || true)
printf 'Selected module (running kernel): %s\n' "${selected:-not-found}"
if [[ $selected == */updates/dkms/snd-hda-codec-conexant.ko* && -n $loaded_src && $loaded_src == "$selected_src" ]]; then
  echo 'Loaded module: matches the selected DKMS module'
elif [[ -z $loaded_src ]]; then
  echo 'Loaded module: not loaded or srcversion unavailable'
else
  echo 'Loaded module: DKMS activation not confirmed (a reboot may be needed)'
fi
printf 'Selected module (installed target): %s\n' "$(modinfo -k "$detected_kernel_release" -n snd_hda_codec_conexant 2>/dev/null || echo not-found)"
[[ $action == check ]] || exit 0
[[ $(uname -m) == x86_64 ]] || die 'Only x86_64 is supported'
detect_hardware
printf 'Hardware: SN6140 %s, supported pins/GPIO and DMIC detected\n' "$codec_ssid"
detect_target "$detected_kernel_release"
printf 'Headers: match %s (%s)\n' "$detected_kernel_release" "$detected_package_version"
for cmd in dkms gcc make curl gpg bsdtar patch xz zstd pacman-key; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd (install the package dependencies)"
done
if [[ -r /sys/module/module/parameters/sig_enforce && $(</sys/module/module/parameters/sig_enforce) == Y ]] ||
   { [[ -r /sys/kernel/security/lockdown ]] && ! grep -Fq '[none]' /sys/kernel/security/lockdown; }; then
  warn 'Signature enforcement/lockdown is active. DKMS signing alone does not prove the key is trusted; verify key enrollment before reboot.'
fi
if [[ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook ]]; then
  echo 'Initramfs: standard mkinitcpio pacman hook detected; verify that it manages your actual boot image'
else
  warn 'Standard mkinitcpio hook not found; check your dracut/UKI initramfs update workflow separately'
fi
# Include retained older kernels: their manual overrides must not be archived
# as DKMS originals during a later install or migration.
for base in "$sn6140_modules_root"/*/pkgbase; do
  [[ -r $base && $(<"$base") == linux-zen ]] || continue
  release=${base%/pkgbase}
  check_legacy_override "${release##*/}"
done
echo 'Preflight passed. This checks compatibility, not real audio or boot-image behavior.'
