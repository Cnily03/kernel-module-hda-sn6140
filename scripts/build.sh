#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build only snd-hda-codec-conexant.ko for a running or DKMS-targeted Arch
# linux-zen kernel.  Nothing is installed into /usr/lib/modules.

set -euo pipefail
IFS=$'\n\t'

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
patch_file="$project_dir/patches/0001-ALSA-hda-conexant-fix-Huawei-CREF-output-routing.patch"
cache_dir="$project_dir/cache"
output_base="$project_dir/dist"
keep_work=0
offline=0
target_package_version=''
target_kernel_release=''
target_codec_ssid=''
assume_topology=0
explicit_target=0
dkms_kernel=''

# Keep CLI handling deliberately small: the builder has no install or load
# switch, so running it as a normal user cannot mutate the active kernel.
usage() {
  cat <<'EOF'
Usage: build.sh [OPTIONS]

Build only snd-hda-codec-conexant.ko for uname -r.  The script downloads and
verifies the exact Arch linux-zen headers package and matching Linux/Zen
sources.  It never installs or loads a module.

Options:
  --cache DIR       Download cache (default: PROJECT/cache)
  --output DIR      Artifact base directory (default: PROJECT/dist)
  --dkms-kernel RELEASE
                    Internal DKMS mode: use installed target headers, not uname
  --offline         Do not download; fail if any cache file is missing
  --keep-work       Keep the temporary build directory for inspection
  --target-package-version VERSION
                    Explicit Arch linux-zen version for hardware-less CI
  --target-kernel-release RELEASE
                    Explicit kernel release paired with the package version
  --codec-subsystem-id ID
                    Explicit 8-hex-digit codec SSID, for example 0x19e5327e
  --assume-sn6140-topology
                    Acknowledge CI cannot inspect NID/GPIO hardware topology
  -h, --help        Show this help

The three explicit target values and --assume-sn6140-topology must be supplied
together. Without them or --dkms-kernel, the script validates live hardware
and the running kernel. DKMS validates hardware separately before installation.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '==> %s\n' "$*"
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

while (($#)); do
  case "$1" in
    --cache)
      (($# >= 2)) || die '--cache requires a directory'
      cache_dir=$2
      shift 2
      ;;
    --output)
      (($# >= 2)) || die '--output requires a directory'
      output_base=$2
      shift 2
      ;;
    --dkms-kernel)
      (($# >= 2)) || die '--dkms-kernel requires a release'
      dkms_kernel=$2
      shift 2
      ;;
    --offline)
      offline=1
      shift
      ;;
    --keep-work)
      keep_work=1
      shift
      ;;
    --target-package-version)
      (($# >= 2)) || die '--target-package-version requires a value'
      target_package_version=$2
      shift 2
      ;;
    --target-kernel-release)
      (($# >= 2)) || die '--target-kernel-release requires a value'
      target_kernel_release=$2
      shift 2
      ;;
    --codec-subsystem-id)
      (($# >= 2)) || die '--codec-subsystem-id requires a value'
      target_codec_ssid=${2,,}
      shift 2
      ;;
    --assume-sn6140-topology)
      assume_topology=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

explicit_value_count=0
[[ -n $target_package_version ]] && ((explicit_value_count += 1))
[[ -n $target_kernel_release ]] && ((explicit_value_count += 1))
[[ -n $target_codec_ssid ]] && ((explicit_value_count += 1))
if ((explicit_value_count > 0 || assume_topology)); then
  [[ $explicit_value_count -eq 3 && $assume_topology -eq 1 ]] || \
    die 'Explicit CI mode requires all three target values and --assume-sn6140-topology'
  [[ $target_package_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.zen[0-9]+-[0-9]+$ ]] || \
    die "Invalid Arch package version: $target_package_version"
  [[ $target_kernel_release =~ ^[A-Za-z0-9._+-]+$ ]] || \
    die "Invalid target kernel release: $target_kernel_release"
  [[ $target_codec_ssid =~ ^0x[0-9a-f]{8}$ ]] || \
    die "Invalid codec subsystem ID: $target_codec_ssid"
  explicit_target=1
fi

if [[ -n $dkms_kernel ]]; then
  [[ $dkms_kernel =~ ^[0-9][A-Za-z0-9._+-]*-zen$ ]] || die 'Invalid DKMS linux-zen release'
  ((explicit_target == 0)) || die 'DKMS and explicit CI modes are mutually exclusive'
fi

for cmd in awk bsdtar cat cp curl gcc gpg gpgv grep head install make mktemp modinfo mv \
  pacman pacman-key patch sed sha256sum uname xz zgrep zstd; do
  need "$cmd"
done

[[ -n $dkms_kernel ]] || ((EUID != 0)) || die 'Run this builder as a normal user, not root'
[[ -r $patch_file ]] || die "Patch not found: $patch_file"

# Explicit mode exists for hardware-less CI runners.  Normal local operation
# still derives every value from the live system and validates the codec pins.
kernel_package=linux-zen
codec_vendor=0x14f11f87
if [[ -n $dkms_kernel ]]; then
  # DKMS runs before reboot: never use uname -r or /proc/config.gz here.
  source "$project_dir/scripts/lib/detect.sh"
  kernel_release=$dkms_kernel
  detect_target "$kernel_release"
  package_version=$detected_package_version
  build_tree=$detected_build_tree
  selected_module_path='dkms-target'
  package_module_path='dkms-managed-original'
  codec_ssid=0x19e5327e
  codec_dump='fixed-supported-quirk:hardware-checked-before-install'
elif ((explicit_target)); then
  kernel_release=$target_kernel_release
  package_version=$target_package_version
  codec_ssid=$target_codec_ssid
  selected_module_path='explicit-ci-target'
  package_module_path='explicit-ci-target'
  codec_dump='explicit-ci-target:no-live-hardware-validation'
else
  # Resolve the exact Arch package that supplied the module selected for the
  # running kernel.  Guessing from uname alone would miss Arch pkgrel rebuilds.
  kernel_release=$(uname -r)
  selected_module_path=$(modinfo -n snd_hda_codec_conexant 2>/dev/null) || \
    die 'The running kernel does not expose snd_hda_codec_conexant as a module'
  [[ -f $selected_module_path ]] || die "Selected module not found: $selected_module_path"

  # An already active updates/ override is intentionally not owned by pacman.
  # Fall back to the distribution copy under kernel/ so repeated builds still
  # resolve the exact package version without removing the working override.
  package_module_path=$selected_module_path
  kernel_package=$(pacman -Qoq "$package_module_path" 2>/dev/null | head -n1 || true)
  if [[ -z $kernel_package ]]; then
    for candidate in \
      "/usr/lib/modules/$kernel_release/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko"*; do
      [[ -f $candidate ]] || continue
      candidate_package=$(pacman -Qoq "$candidate" 2>/dev/null | head -n1 || true)
      if [[ -n $candidate_package ]]; then
        package_module_path=$candidate
        kernel_package=$candidate_package
        break
      fi
    done
  fi
  [[ -n $kernel_package ]] || \
    die "Could not find a pacman-owned distribution copy for $selected_module_path"
  [[ $kernel_package == linux-zen ]] || \
    die "This revision supports Arch linux-zen only; found package: $kernel_package"
  IFS=' ' read -r queried_name package_version < <(pacman -Q "$kernel_package")
  [[ $queried_name == "$kernel_package" && -n $package_version ]] || \
    die "Could not resolve the installed package version for $kernel_package"

  config_value=''
  if [[ -r /proc/config.gz ]]; then
    config_value=$(zgrep '^CONFIG_SND_HDA_CODEC_CONEXANT=' /proc/config.gz || true)
  fi
  [[ $config_value == 'CONFIG_SND_HDA_CODEC_CONEXANT=m' ]] || \
    die "Conexant codec is not a replaceable module in the running config: ${config_value:-unknown}"

  # The produced module is intentionally unsigned because the Arch build-time
  # private key is unavailable.  Refuse if the running policy would reject it.
  if [[ -r /sys/module/module/parameters/sig_enforce ]] &&
     [[ $(</sys/module/module/parameters/sig_enforce) == Y ]]; then
    die 'The running kernel enforces module signatures; an unsigned local module would not load'
  fi
  if [[ -r /sys/kernel/security/lockdown ]]; then
    lockdown_state=$(</sys/kernel/security/lockdown)
    [[ $lockdown_state == *'[none]'* ]] || \
      die "Kernel lockdown is active: $lockdown_state"
  fi

  source "$project_dir/scripts/lib/detect.sh"
  detect_hardware

fi

[[ $codec_ssid == 0x19e5327e ]] || die 'Unsupported codec subsystem ID; a different board needs its own quirk'

arch=$(uname -m)
[[ $arch == x86_64 ]] || die "Only x86_64 is supported; found $arch"

# Arch package version: 7.1.8.zen1-3 -> upstream 7.1.8, Zen revision zen1.
# Both pieces are needed to retrieve the same base tarball and Zen patch that
# produced the installed Arch package.
epochless_version=${package_version#*:}
package_pkgver=${epochless_version%-*}
linux_version=${package_pkgver%.*}
zen_revision=${package_pkgver##*.}
[[ $linux_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  die "Cannot derive upstream Linux version from $package_version"
[[ $zen_revision =~ ^zen[0-9]+$ ]] || \
  die "Cannot derive Zen revision from $package_version"

headers_package="${kernel_package}-headers"
headers_archive="${headers_package}-${package_version}-${arch}.pkg.tar.zst"
linux_archive="linux-${linux_version}.tar.xz"
linux_signature="linux-${linux_version}.tar.sign"
zen_archive="linux-v${linux_version}-${zen_revision}.patch.zst"

mkdir -p -- "$cache_dir" "$output_base" "$project_dir/.work"
work_dir=$(mktemp -d "$project_dir/.work/module-${kernel_release}.XXXXXX")

# All intermediate trees are disposable.  --keep-work is intended only for
# auditing a failed build; downloads remain separately cached.
cleanup() {
  if ((keep_work)); then
    printf '==> Kept work directory: %s\n' "$work_dir"
  else
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

download() {
  local url=$1
  local destination=$2
  if [[ -s $destination ]]; then
    note "Using cached $(basename -- "$destination")"
    return
  fi
  ((offline == 0)) || die "Offline cache miss: $destination"
  note "Downloading $(basename -- "$destination")"
  curl --fail --location --proto '=https' --tlsv1.2 \
    --connect-timeout 20 --max-time 1800 --retry 3 --output "$destination.part" "$url"
  mv -- "$destination.part" "$destination"
}

# Use primary distribution/upstream locations.  Every downloaded binary is
# authenticated below; HTTPS is transport protection, not the trust anchor.
archive_base='https://archive.archlinux.org/packages/l/linux-zen-headers'
kernel_base="https://cdn.kernel.org/pub/linux/kernel/v${linux_version%%.*}.x"
zen_base="https://github.com/zen-kernel/zen-kernel/releases/download/v${linux_version}-${zen_revision}"

if [[ -z $dkms_kernel ]]; then
  download "$archive_base/$headers_archive" "$cache_dir/$headers_archive"
  download "$archive_base/$headers_archive.sig" "$cache_dir/$headers_archive.sig"
fi
download "$kernel_base/$linux_archive" "$cache_dir/$linux_archive"
download "$kernel_base/$linux_signature" "$cache_dir/$linux_signature"
download "$zen_base/$zen_archive" "$cache_dir/$zen_archive"
download "$zen_base/$zen_archive.sig" "$cache_dir/$zen_archive.sig"

if [[ -z $dkms_kernel ]]; then
  note 'Verifying the archived Arch headers package'
  pacman-key --verify "$cache_dir/$headers_archive.sig" "$cache_dir/$headers_archive"
fi

# A private temporary keyring avoids adding build-only keys to ~/.gnupg.  The
# cached public-key bundle makes later --offline builds genuinely offline.
gpg_home="$work_dir/gnupg"
mkdir -m 700 -- "$gpg_home"
key_bundle="$cache_dir/linux-zen-source-signing-keys.gpg"
if [[ ! -s $key_bundle ]]; then
  ((offline == 0)) || die "Offline signing-key cache miss: $key_bundle"
  note 'Fetching pinned source-signing public keys'
  for fingerprint in 647F28654894E3BD457199BE38DBBDC86092693E 83BC8889351B5DEBBB68416EB8AC08600F108CDF; do
    curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 20 --max-time 120 --retry 3 \
      "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fingerprint" \
      -o "$work_dir/$fingerprint.asc"
    cat "$work_dir/$fingerprint.asc" >> "$work_dir/signing-keys.asc"
  done
  # A public-key ring needs no gpg-agent, dirmngr, trustdb or private key.
  GNUPGHOME="$gpg_home" gpg --no-options --batch --dearmor < "$work_dir/signing-keys.asc" > "$key_bundle.part"
  mv -- "$key_bundle.part" "$key_bundle"
fi

note 'Verifying Linux and Zen source signatures'
xz -dc "$cache_dir/$linux_archive" > "$work_dir/linux-${linux_version}.tar"
verify_source() {
  local signature=$1 data=$2 fingerprint=$3
  gpgv --homedir "$gpg_home" --keyring "$key_bundle" --status-fd 1 "$signature" "$data" > "$work_dir/signature-status"
  # Accept the pinned primary key or one of its signing subkeys only.
  awk -v wanted="$fingerprint" '$2 == "VALIDSIG" && ($3 == wanted || $NF == wanted) { valid = 1 } END { exit !valid }' \
    "$work_dir/signature-status" || die "Unexpected signer for $signature"
}
verify_source "$cache_dir/$linux_signature" "$work_dir/linux-${linux_version}.tar" 647F28654894E3BD457199BE38DBBDC86092693E
verify_source "$cache_dir/$zen_archive.sig" "$cache_dir/$zen_archive" 83BC8889351B5DEBBB68416EB8AC08600F108CDF

headers_root="$work_dir/headers-root"
source_root="$work_dir/source-root"
mkdir -p -- "$headers_root" "$source_root"
note 'Extracting exact headers and sources'
if [[ -z $dkms_kernel ]]; then
  bsdtar -xf "$cache_dir/$headers_archive" -C "$headers_root"
  build_tree="$headers_root/usr/lib/modules/$kernel_release/build"
fi
bsdtar -xf "$work_dir/linux-${linux_version}.tar" -C "$source_root"

source_tree="$source_root/linux-$linux_version"
[[ -d $build_tree ]] || die "Headers package does not contain build tree for $kernel_release"
[[ -s $build_tree/Module.symvers ]] || die 'Exact headers tree has no Module.symvers'
[[ -r $source_tree/sound/hda/codecs/conexant.c ]] || die 'Conexant source is missing'
grep -Fq "\"$kernel_release\"" "$build_tree/include/generated/utsrelease.h" || \
  die 'Headers release does not match the build target'
grep -Fq 'CONFIG_SND_HDA_CODEC_CONEXANT=m' "$build_tree/.config" || \
  die 'Target kernel config does not build the Conexant codec as a module'

# Compare against the compiler recorded in the exact headers package.  This is
# available both locally and in CI, unlike /proc/version on a cloud runner.
expected_gcc=$(sed -n 's/.*gcc (GCC) \([0-9][0-9.]*\).*/\1/p' \
  "$build_tree/include/generated/compile.h")
host_gcc=$(gcc -dumpfullversion)
[[ -z $expected_gcc || $expected_gcc == "$host_gcc" ]] || \
  die "Compiler mismatch: target kernel used GCC $expected_gcc, builder has GCC $host_gcc"

# Recreate the distribution source state in order: upstream Linux, Zen patch,
# then this repository's SN6140 patch.  --fuzz=0 prevents approximate merging.
note 'Applying the exact Zen source patch'
zstd -dc "$cache_dir/$zen_archive" > "$work_dir/zen.patch"
patch --batch --forward --fuzz=0 -d "$source_tree" -Np1 < "$work_dir/zen.patch"

note 'Applying the SN6140 routing patch'
patch --batch --forward --fuzz=0 -d "$source_tree" -Np1 < "$patch_file"

# Replace the RFC PCI-controller match with the known supported codec SSID.
# Live detection verifies this ID; DKMS never invents a new hardware quirk.
codec_subvendor=${codec_ssid:2:4}
codec_subdevice=${codec_ssid:6:4}
conexant_source="$source_tree/sound/hda/codecs/conexant.c"
old_quirk='SND_PCI_QUIRK(0x19e5, 0x3e5f, "Huawei MateBook 16s CREF-XX", CXT_FIXUP_HUAWEI_CREF),'
new_quirk="HDA_CODEC_QUIRK(0x${codec_subvendor}, 0x${codec_subdevice}, \"Huawei SN6140 supported codec SSID\", CXT_FIXUP_HUAWEI_CREF),"
grep -Fq "$old_quirk" "$conexant_source" || die 'Could not locate the newly added PCI quirk'
awk -v old="$old_quirk" -v new="$new_quirk" '
  {
    pos = index($0, old)
    if (pos)
      $0 = substr($0, 1, pos - 1) new substr($0, pos + length(old))
    print
  }
' "$conexant_source" \
  > "$work_dir/conexant.c"
mv -- "$work_dir/conexant.c" "$conexant_source"
grep -Fq "$new_quirk" "$conexant_source" || die 'Codec-SSID quirk generation failed'

module_source="$work_dir/module-source"
mkdir -p -- "$module_source/common"

# conexant.c uses private HDA headers and includes helper C fragments directly;
# Arch's headers package intentionally omits them, so copy only this small,
# exact-version source subset into the external-module directory.
cp -- "$project_dir/module/Makefile" "$module_source/Makefile"
cp -- "$conexant_source" "$module_source/conexant.c"
cp -- "$source_tree/sound/hda/codecs/generic.h" "$module_source/generic.h"
cp -- "$source_tree/sound/hda/common/"*.h "$module_source/common/"
cp -R -- "$source_tree/sound/hda/codecs/helpers" "$module_source/helpers"

# Never mutate the installed DKMS headers. BTF is optional; disable only the
# external module's BTF pass when pahole is unavailable.
btf_state='included'
make_options=()
if ! command -v pahole >/dev/null 2>&1 && [[ -f $build_tree/vmlinux ]]; then
  make_options+=(CONFIG_DEBUG_INFO_BTF_MODULES=)
  btf_state='skipped (pahole unavailable)'
fi

note "Building only snd-hda-codec-conexant.ko for $kernel_release"
make -C "$build_tree" M="$module_source" "${make_options[@]}" modules
module_ko="$module_source/snd-hda-codec-conexant.ko"
[[ -s $module_ko ]] || die 'Kbuild did not produce snd-hda-codec-conexant.ko'

built_vermagic=$(modinfo -F vermagic "$module_ko")
if ((explicit_target)) || [[ -n $dkms_kernel ]]; then
  [[ $built_vermagic == "$kernel_release "* ]] || \
    die "vermagic release mismatch: built '$built_vermagic', target '$kernel_release'"
  reference_vermagic='target-release-checked'
else
  reference_vermagic=$(modinfo -F vermagic snd_hda_codec_conexant)
  [[ $built_vermagic == "$reference_vermagic" ]] || \
    die "vermagic mismatch: built '$built_vermagic', running '$reference_vermagic'"
fi

# Publish both the inspectable ELF module and Arch's normal zstd-compressed form.
# BUILD-INFO records the exact inputs used for later diagnosis and rollback.
output_dir="$output_base/$kernel_release"
mkdir -p -- "$output_dir"
install -m 0644 "$module_ko" "$output_dir/snd-hda-codec-conexant.ko"
zstd -f -T0 -19 "$output_dir/snd-hda-codec-conexant.ko" \
  -o "$output_dir/snd-hda-codec-conexant.ko.zst"

module_sha256=$(sha256sum "$output_dir/snd-hda-codec-conexant.ko" | awk '{print $1}')
cat > "$output_dir/BUILD-INFO.txt" <<EOF
kernel_release=$kernel_release
kernel_package=$kernel_package
kernel_package_version=$package_version
selected_module=$selected_module_path
distribution_module=$package_module_path
reference_vermagic=$reference_vermagic
built_vermagic=$built_vermagic
build_mode=$([[ -n $dkms_kernel ]] && echo dkms-target || { [[ $explicit_target -eq 1 ]] && echo explicit-ci || echo live-auto-detect; })
codec_dump=$codec_dump
codec_vendor=$codec_vendor
codec_subsystem_id=$codec_ssid
quirk_match=codec_ssid:${codec_subvendor}:${codec_subdevice}
module_btf=$btf_state
module_signer=unsigned
module_sha256=$module_sha256
EOF

note 'Build complete; nothing was installed or loaded'
printf 'Artifact: %s\n' "$output_dir/snd-hda-codec-conexant.ko.zst"
printf 'Metadata: %s\n' "$output_dir/BUILD-INFO.txt"
printf 'vermagic: %s\n' "$built_vermagic"
printf 'SHA-256: %s\n' "$module_sha256"
