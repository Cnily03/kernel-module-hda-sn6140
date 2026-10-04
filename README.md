# SN6140 audio fix

[English](README.md) | [简体中文](README.zh-CN.md)

Fixes silent speakers and incorrect headphone switching on the Huawei MateBook 16s
(CREF-XX/M1010). The Arch DKMS package rebuilds the driver automatically when
`linux-zen` is updated, with no kernel versions or codec IDs to enter.
Only the Conexant module is built; SOF and the digital microphone are preserved.

Supports **Arch Linux x86_64 + linux-zen**, with SN6140 `14f1:1f87 / 19e5:327e`.
This fix is experimental. Start at low volume and keep a fallback kernel.

## Install

Install dependencies:

```sh
sudo pacman -Syu --needed base-devel dkms linux-zen linux-zen-headers \
  curl gnupg libarchive patch kmod xz zstd
```

From the repository directory, check the environment, build and install the package:

```sh
make doctor
make package
sudo pacman -U dist/packages/sn6140-linux-zen-dkms-0.2.0-1-x86_64.pkg.tar.zst
```

Installation downloads, verifies and compiles the driver for the target kernel;
Internet access and several GiB of temporary space are required.
Reboot after DKMS and boot image updates succeed, then check:

```sh
sn6140 status
```

The module path should be under `updates/dkms/`, with the loaded module matching it.

## Update and uninstall

Use `sudo pacman -Syu` as usual. Keep `linux-zen-headers` installed; rebuilding
the package for each kernel update is unnecessary. For build failures, Secure Boot
or custom boot images, see the [maintenance guide](docs/ARCH.md).

Remove the fix and restore the original driver:

```sh
sudo pacman -R sn6140-linux-zen-dkms
sudo reboot
```

## Documentation

- [Installation, maintenance and troubleshooting](docs/ARCH.md)
- [Driver internals and build design](docs/TECHNICAL.md)
- [Testing](docs/TESTING.md)

License: [GPL-2.0-or-later](COPYING).
