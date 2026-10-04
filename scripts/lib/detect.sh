#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Shared read-only probes. Caller supplies die(); roots are replaceable in tests.
sn6140_modules_root=/usr/lib/modules
sn6140_asound_root=/proc/asound

detect_hardware() {
  local node16 node17
  local -a codecs
  mapfile -t codecs < <(grep -l -x 'Codec: Conexant SN6140' "$sn6140_asound_root"/card*/codec\#* 2>/dev/null || true)
  [[ ${#codecs[@]} -eq 1 ]] || die "Expected exactly one SN6140 codec; found ${#codecs[@]}"
  codec_dump=${codecs[0]}
  codec_vendor=$(awk '/^Vendor Id:/ { print tolower($3); exit }' "$codec_dump")
  codec_ssid=$(awk '/^Subsystem Id:/ { print tolower($3); exit }' "$codec_dump")
  [[ $codec_vendor == 0x14f11f87 && $codec_ssid == 0x19e5327e ]] || \
    die "Unsupported codec: vendor=$codec_vendor subsystem=$codec_ssid (expected 0x14f11f87/0x19e5327e)"
  node16=$(node_block 0x16)
  node17=$(node_block 0x17)
  grep -Fq '[Jack] HP Out' <<< "$node16" || die 'NID 0x16 is not the expected headphone pin'
  grep -Fq 'Connection: 2' <<< "$node16" || die 'NID 0x16 lacks the two-way selector'
  grep -Fq '[Fixed] Speaker' <<< "$node17" || die 'NID 0x17 is not the expected speaker pin'
  grep -Fq 'Connection: 2' <<< "$node17" || die 'NID 0x17 lacks the two-way selector'
  grep -Fq 'IO[1]: enable=1, dir=1' "$codec_dump" || die 'GPIO1 is not enabled as an output'
  grep -q 'DMIC' "$sn6140_asound_root/pcm" || die 'DMIC endpoint is missing; check SOF firmware/topology first'
}

node_block() {
  awk -v wanted="$1" '
    $1 == "Node" && $2 == wanted { active = 1 }
    active && $1 == "Node" && $2 != wanted { exit }
    active { print }
  ' "$codec_dump"
}

detect_installed_kernel() {
  local path
  local -a targets=()
  while IFS= read -r path; do
    [[ $path == /usr/lib/modules/*/pkgbase ]] || continue
    path=${path%/pkgbase}
    targets+=("${path##*/}")
  done < <(pacman -Qlq linux-zen)
  [[ ${#targets[@]} -eq 1 ]] || die 'Cannot uniquely identify the installed linux-zen kernel from pacman'
  detected_kernel_release=${targets[0]}
}

detect_target() {
  local release=$1 package_name headers_name headers_version recorded
  [[ $release =~ ^[0-9][A-Za-z0-9._+-]*-zen$ ]] || die "Not a linux-zen release: $release"
  detected_build_tree="$sn6140_modules_root/$release/build"
  [[ -r $sn6140_modules_root/$release/pkgbase ]] || die "Missing pkgbase for $release"
  [[ $(<"$sn6140_modules_root/$release/pkgbase") == linux-zen ]] || die 'Target is not Arch linux-zen'
  [[ -s $detected_build_tree/Module.symvers ]] || die "Install matching linux-zen-headers: missing Module.symvers for $release"
  [[ -r $detected_build_tree/include/config/kernel.release ]] || die 'Headers have no kernel.release'
  recorded=$(<"$detected_build_tree/include/config/kernel.release")
  [[ $recorded == "$release" ]] || die "Headers release mismatch: $recorded != $release"
  grep -qx 'CONFIG_SND_HDA_CODEC_CONEXANT=m' "$detected_build_tree/.config" || die 'Conexant must be configured as a module (=m)'
  [[ $(pacman -Qoq "$sn6140_modules_root/$release/pkgbase") == linux-zen ]] || die 'Target is not owned by linux-zen'
  [[ $(pacman -Qoq "$detected_build_tree/Module.symvers") == linux-zen-headers ]] || die 'Headers are not owned by linux-zen-headers'
  IFS=' ' read -r package_name detected_package_version < <(pacman -Q linux-zen)
  IFS=' ' read -r headers_name headers_version < <(pacman -Q linux-zen-headers)
  [[ $package_name == linux-zen && $headers_name == linux-zen-headers && -n $detected_package_version && $detected_package_version == "$headers_version" ]] || \
    die 'linux-zen and linux-zen-headers package versions differ; complete the system upgrade first'
}

check_legacy_override() {
  local file
  for file in "$sn6140_modules_root/$1/updates/sn6140/"snd-hda-codec-conexant.ko*; do
    [[ ! -e $file ]] || die "Manual override exists: $file. Use the old manage.sh rollback for that kernel before DKMS installation."
  done
}
