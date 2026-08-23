# SN6140 build, test, and rollback guide

[English](TESTING.md) | [简体中文](TESTING.zh-CN.md) | [Project home](../README.md)

This guide separates read-only work from system changes. Collection and build
steps run as an unprivileged user. Only the explicitly marked install and
rollback commands require sudo.

> [!CAUTION]
> Before installation, keep a known-good unmodified kernel that you have
> actually verified can be selected from the boot menu. If you do not know how
> to select it, stop after building. A completed module does not have to be
> installed immediately.

## 0. Quick preflight

From the repository root:

```sh
uname -r
pacman -Q linux-zen
zgrep '^CONFIG_SND_HDA_CODEC_CONEXANT=' /proc/config.gz
```

Continue only when the running kernel is `linux-zen`, pacman has its matching
package, and the driver setting is `CONFIG_SND_HDA_CODEC_CONEXANT=m`.

| Failed check | Meaning | What to do |
| --- | --- | --- |
| Pacman is newer than `uname -r` | Installed and running kernels differ | Reboot into the new kernel and check again; do not mix headers |
| Setting is `=y` | Driver is built into the kernel | Stop the single-`.ko` procedure and use a complete revertible kernel package |
| `/proc/config.gz` is absent | Running configuration is not exposed | Check `.config` from headers matching `uname -r`; do not install until `m` is proven |
| Kernel is not Arch `linux-zen` | Automated source/ABI path is unsupported | Add support for that distribution instead of fabricating target values |

## 1. Save a before baseline

```sh
./scripts/collect-sn6140.sh report.sn6140.before.txt
./scripts/manage.sh status
```

The report is stored at `reports/report.sn6140.before.txt`. It reads hardware
and kernel state but does not record audio, load modules, or change mixer state.

```sh
grep -E 'Codec:|Vendor Id:|Subsystem Id:|Node 0x16|Node 0x17|IO\[1\]|HDA Analog|DMIC' \
  reports/report.sn6140.before.txt
```

The supported baseline includes SN6140 vendor `0x14f11f87`, headphone NID
`0x16`, speaker NID `0x17`, GPIO1, and separate `HDA Analog`, `DMIC`, and
`DMIC16kHz` endpoints.

> [!WARNING]
> If codec/vendor differs, this is not the target hardware. If NID/GPIO differs,
> retain the report and develop a separate quirk instead of bypassing topology
> validation. If only DMIC is missing, restore the correct SOF firmware,
> machine driver, and topology first; this output patch cannot create DSP PCMs.

## 2. Build as an unprivileged user

```sh
./scripts/build.sh
```

The first build downloads and verifies exact headers, Linux source, and the Zen
patch. Successful output is stored under `dist/$(uname -r)/`.

| Build failure | Correct response |
| --- | --- |
| Missing `gcc`, `gpg`, `bsdtar`, or `zstd` | Identify and install the owning Arch package, then rerun as a normal user |
| Download or GPG verification failed | Check system time and `archlinux-keyring`; retry with verified downloads when networking works |
| Package version differs from `uname -r` | Reboot into the kernel matching the installed package and rebuild |
| Topology or SSID validation failed | Keep the baseline report and stop installation; this hardware needs separate analysis |
| Permission denied in the repository | Check whether an earlier sudo command made files root-owned; restore ownership and build unprivileged |

After a complete online download, `./scripts/build.sh --offline` can rebuild
from `cache/`. If it reports a missing cache item, remove `--offline` and retry
when networking is available.

## 3. Verify the output

```sh
kernel_release=$(uname -r)
dist_dir="dist/$kernel_release"
cat "$dist_dir/BUILD-INFO.txt"
modinfo "$dist_dir/snd-hda-codec-conexant.ko"
zstd -t "$dist_dir/snd-hda-codec-conexant.ko.zst"
```

The recorded release must equal `uname -r`; built and original vermagic must
match; vendor must be `0x14f11f87`; subsystem ID must match the baseline; and
the compression test must succeed.

> [!WARNING]
> Renaming, recompressing, or force-loading cannot fix any mismatch. Discard
> that release's output and rebuild while the correct target kernel is running.
> A different SSID/topology requires a new quirk, not another identical build.

## 4. Check initramfs

```sh
lsinitcpio -a /boot/initramfs-linux-zen.img | \
  grep -E 'snd[-_]hda[-_]codec[-_]conexant|conexant'
```

- No output: continue; the disk override can normally be selected.
- Output appears: stop installation because the old module may load before the
  root filesystem is mounted.

When output appears, identify whether mkinitcpio, dracut, or a UKI owns the boot
image and back up a known-good image. If you cannot restore it, do not rebuild
initramfs; retaining the already-built `dist/` files is safe.

## 5. Install

First inspect current state:

```sh
./scripts/manage.sh status
```

A first install normally reports `override_file=absent` and
`active_override=no`. If an override is active, compare srcversion or roll it
back instead of installing over it. If a file is present but inactive, compare
its path's release with `uname -r`; do not force-load it.

Close every audio application, reduce volume, and run:

```sh
sudo ./scripts/manage.sh install
sudo reboot
```

The installer adds only the compressed override under
`/usr/lib/modules/<release>/updates/sn6140/` and runs `depmod`. It does not
overwrite the distribution module or hot-unload HDA/SOF.

> [!WARNING]
> If installation fails, do not manually copy the module or overwrite files
> under `kernel/sound/`. Retain the error and run `manage.sh status`. If no
> override is present, correct the original error before retrying; if partially
> present, roll it back first.

## 6. Validate after reboot

### Confirm the override is active

```sh
./scripts/manage.sh status
```

Expected:

```text
selected_module=.../updates/sn6140/snd-hda-codec-conexant.ko.zst
override_file=present
active_override=yes
```

If selection still points to `kernel/sound/`, check that `uname -r` is the
installed target and inspect `depmod -n`. Do not hot-unload the sound stack;
roll back if the override cannot be proven active.

```sh
./scripts/collect-sn6140.sh report.sn6140.after.txt
journalctl -k -b | grep -Ei 'snd|sof|hda|SN6140|error|warn'
```

The report is `reports/report.sn6140.after.txt`.

### Low-volume playback and simultaneous DMIC recording

Terminal A:

```sh
speaker-test -D hw:sofhdadsp,0 -c 2 -r 48000 -t sine
```

Terminal B, replacing device `6` with the DMIC device from `/proc/asound/pcm`:

```sh
arecord -D hw:sofhdadsp,6 -f S16_LE -r 48000 -c 4 \
  -d 10 /tmp/sn6140-dmic.wav
aplay /tmp/sn6140-dmic.wav
```

If `arecord` says the device does not exist, do not guess numbers. Re-read the
PCM list. If the DMIC entry disappeared, retain logs and roll back.

### Headphone, repetition, and suspend tests

At low volume verify speaker-only output without headphones, headphone-only
output after insertion, speaker recovery after removal, at least ten repeated
cycles, the same sequence after suspend/resume, and DMIC recording in every
output state.

> [!CAUTION]
> Pops, feedback, simultaneous outputs, total silence, codec timeout, SOF IPC
> errors, or a disappearing DMIC are failures. Stop playback immediately,
> retain both reports and the kernel log, and roll back. Do not continue until
> an intermittent working state appears.

## 7. Roll back

When the current kernel boots:

```sh
sudo ./scripts/manage.sh rollback
sudo reboot
```

After reboot, status must show `override_file=absent`, `active_override=no`, and
the distribution module under `kernel/sound/hda/codecs/`. If the override
remains, compare its exact path with `uname -r`; do not repeatedly reboot or
delete a broad directory.

If the affected kernel does not boot, select the known-good kernel, identify
the exact affected release, remove only
`updates/sn6140/snd-hda-codec-conexant.ko.zst` under that release, then run
`sudo depmod <affected-release>`.

> [!CAUTION]
> Never remove all of `/usr/lib/modules`, an entire release directory, or the
> distribution module under `kernel/sound/hda/codecs/`. If the affected release
> is ambiguous, preserve the system and ask for help instead of recursively
> deleting files.
