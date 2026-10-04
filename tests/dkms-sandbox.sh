#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Exercise real DKMS with a read-only host and disposable module/database trees.
# Requires bubblewrap, the package dependencies and supported live hardware.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$project_dir/PKGBUILD"
source "$project_dir/scripts/lib/detect.sh"
die() { echo "ERROR: $*" >&2; exit 1; }
((EUID != 0)) || die 'Run the sandbox test as a normal user'
detect_installed_kernel
detect_target "$detected_kernel_release"
package_file="$project_dir/dist/packages/$pkgname-$pkgver-$pkgrel-x86_64.pkg.tar.zst"
[[ -f $package_file ]] || die 'Run make package first'
mkdir -p "$project_dir/.work" "$project_dir/cache"
work=$(mktemp -d "$project_dir/.work/dkms-sandbox.XXXXXX")
trap 'result=$?; if ((result == 0)); then rm -rf -- "$work"; else echo "Kept failed sandbox: $work" >&2; fi' EXIT
mkdir -p "$work/package" "$work/modules/$detected_kernel_release" "$work/dkms"
bsdtar -xf "$package_file" -C "$work/package"
# Copy only the distribution module; never copy the active manual override.
cp -a --reflink=auto "$detected_build_tree" "$work/modules/$detected_kernel_release/build"
cp "$sn6140_modules_root/$detected_kernel_release/pkgbase" "$work/modules/$detected_kernel_release/pkgbase"
cp "$sn6140_modules_root/$detected_kernel_release/modules.order" "$work/modules/$detected_kernel_release/modules.order"
cp "$sn6140_modules_root/$detected_kernel_release/"modules.builtin* "$work/modules/$detected_kernel_release/"
mkdir -p "$work/modules/$detected_kernel_release/kernel/sound/hda/codecs"
cp "$sn6140_modules_root/$detected_kernel_release/kernel/sound/hda/codecs/"snd-hda-codec-conexant.ko* \
  "$work/modules/$detected_kernel_release/kernel/sound/hda/codecs/"
cat > "$work/framework.conf" <<'CONF'
try_sign_modules=false
modprobe_on_install=""
post_transaction=""
CONF
cat > "$work/run.sh" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
release=$1
version=$2
original=(/usr/lib/modules/"$release"/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko*)
before=$(sha256sum "${original[0]}")
depmod -a "$release"
dkms add -m sn6140 -v "$version"
dkms build -m sn6140 -v "$version" -k "$release"
# A manual override must block installation without moving the original.
legacy="/usr/lib/modules/$release/updates/sn6140/snd-hda-codec-conexant.ko"
mkdir -p "${legacy%/*}"
touch "$legacy"
if dkms install -m sn6140 -v "$version" -k "$release"; then
  echo 'ERROR: legacy override was not rejected' >&2
  exit 1
fi
[[ $(sha256sum "${original[0]}") == "$before" ]]
rm "$legacy"
# Replay the real pacman DKMS hook's kernel-update target, including depmod.
printf 'usr/lib/modules/%s/build/include/\n' "$release" | /usr/share/libalpm/scripts/dkms install
selected=$(modinfo -k "$release" -n snd_hda_codec_conexant)
[[ $selected == */updates/dkms/snd-hda-codec-conexant.ko* ]]
[[ $(modinfo -F vermagic "$selected") == "$release "* ]]
dkms status -m sn6140
dkms remove -m sn6140 -v "$version" --all
[[ $(sha256sum "${original[0]}") == "$before" ]]
selected=$(modinfo -k "$release" -n snd_hda_codec_conexant)
[[ $selected == */kernel/sound/hda/codecs/snd-hda-codec-conexant.ko* ]]
echo 'PASS: DKMS build, conflict rejection, pacman hook selection and byte-identical original restoration'
RUN
bwrap --unshare-user --uid 0 --gid 0 --ro-bind / / \
  --bind "$work" "$work" --dev /dev --proc /proc --tmpfs /tmp \
  --bind "$work/package/usr/src" /usr/src \
  --bind "$work/modules" /usr/lib/modules \
  --bind "$work/dkms" /var/lib/dkms \
  --tmpfs /var/cache --bind "$project_dir/cache" /var/cache/sn6140 \
  --tmpfs /etc/dkms --ro-bind "$work/framework.conf" /etc/dkms/framework.conf \
  bash "$work/run.sh" "$detected_kernel_release" "$pkgver"
