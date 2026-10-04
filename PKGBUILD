# Maintainer: Cnily03
# SPDX-License-Identifier: GPL-2.0-or-later
pkgname=sn6140-linux-zen-dkms
pkgver=0.2.0
pkgrel=1
pkgdesc='Huawei MateBook 16s SN6140 audio routing fix, rebuilt automatically for Arch linux-zen'
arch=('x86_64')
url='https://github.com/Cnily03/kernel-module-hda-sn6140'
license=('GPL-2.0-or-later')
# This package intentionally supports only linux-zen; matching headers are
# required for unattended upgrades, rather than being an optional dependency.
depends=('dkms' 'linux-zen' 'linux-zen-headers' 'gcc' 'make' 'curl' 'gnupg'
         'libarchive' 'patch' 'kmod' 'xz' 'zstd')
options=('!strip' '!debug')
# scripts/package.sh snapshots only these repository inputs into SRCDEST.
source=('sn6140-source.tar')
sha256sums=('SKIP')

package() {
  local dest="$pkgdir/usr/src/sn6140-$pkgver"
  install -Dm755 "$srcdir/scripts/build.sh" "$dest/scripts/build.sh"
  install -Dm755 "$srcdir/scripts/dkms-build.sh" "$dest/scripts/dkms-build.sh"
  install -Dm755 "$srcdir/scripts/dkms-pre-install.sh" "$dest/scripts/dkms-pre-install.sh"
  install -Dm644 "$srcdir/scripts/lib/detect.sh" "$dest/scripts/lib/detect.sh"
  install -Dm644 "$srcdir/module/Makefile" "$dest/module/Makefile"
  install -Dm644 "$srcdir/patches/0001-ALSA-hda-conexant-fix-Huawei-CREF-output-routing.patch" \
    "$dest/patches/0001-ALSA-hda-conexant-fix-Huawei-CREF-output-routing.patch"
  sed "s/@VERSION@/$pkgver/" "$srcdir/packaging/arch/dkms.conf" > "$dest/dkms.conf"
  install -Dm755 "$srcdir/scripts/doctor.sh" "$pkgdir/usr/lib/sn6140/doctor.sh"
  install -Dm644 "$srcdir/scripts/lib/detect.sh" "$pkgdir/usr/lib/sn6140/lib/detect.sh"
  install -dm755 "$pkgdir/usr/bin"
  ln -s ../lib/sn6140/doctor.sh "$pkgdir/usr/bin/sn6140"
}
