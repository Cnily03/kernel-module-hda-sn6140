# kernel-module-hda-sn6140

[English](README.md) | [简体中文](README.zh-CN.md)

An experimental Linux kernel driver fix for the Conexant SN6140 codec in the
Huawei MateBook 16s `CREF-XX/M1010`. The repository builds only an exact
`snd-hda-codec-conexant.ko` for the target Arch Linux `linux-zen` kernel; it
does not rebuild or replace the complete kernel.

> [!CAUTION]
> This patch directly controls the codec connection selector, speaker EAPD,
> and GPIO1. A wrong hardware match or route transition can cause loud pops,
> simultaneous speaker/headphone output, or persistent silence. Start at low
> volume, keep a known-good unmodified kernel in the boot menu, and never
> install a module built for a different kernel release.

## What problem does this solve?

On this machine, Intel SOF/DSP normally already exposes separate audio
endpoints:

- `HDA Analog` for speakers, headphones, and analog input;
- `DMIC` for the internal digital microphone array;
- `DMIC16kHz` for a low-rate digital microphone endpoint;
- HDMI/DisplayPort digital outputs.

The failure is in the non-standard SN6140 analog output wiring, not in the DSP
endpoint split. On the verified CREF hardware:

- headphone pin is NID `0x16`;
- internal speaker pin is NID `0x17`;
- the selector on NID `0x16` also affects the speaker path;
- EAPD on NID `0x17` controls the external speaker amplifier;
- GPIO1 additionally gates the headphone path.

The generic Conexant automute code does not know these controls are coupled.
Typical symptoms include a silent speaker with no headphones connected,
speaker output continuing after headphone insertion, a silent headphone path,
routes reversing after repeated jack events, and user-space HDA verb fixes
disappearing after reboot or suspend. Playing output while recording can then
look like a microphone/speaker conflict even though the DSP endpoints exist.

## How does the fix work?

The patch modifies `sound/hda/codecs/conexant.c` and registers an SN6140
automute hook for a matching codec subsystem ID. After the generic HDA mute
logic runs, the hook updates these controls as one route transition:

1. connection selector on NID `0x16`;
2. EAPD on speaker NID `0x17`;
3. GPIO1 mask, direction, and output value.

It does not replace SOF with legacy HDA and does not modify the SOF machine
driver, DSP topology, or DMIC PCM definitions. The internal digital microphone
therefore remains a separate DSP endpoint.

The builder also protects against common mismatches by finding the exact Arch
package version, verifying downloaded signatures, using the matching
`.config`, `Module.symvers`, generated headers and compiler, comparing
vermagic, reading the live codec subsystem ID, and validating the expected
NID/GPIO topology. Only `snd-hda-codec-conexant.ko` is compiled.

> [!NOTE]
> `scripts/build.sh` runs without sudo. It downloads and builds into the
> repository, but never installs a module or changes `/boot`, `/etc`, or the
> running kernel.

## Supported configuration

The automated local path currently supports:

- Arch Linux x86_64 with `linux-zen`;
- `CONFIG_SND_HDA_CODEC_CONEXANT=m`;
- Conexant SN6140 vendor ID `0x14f11f87`;
- headphone NID `0x16`, speaker NID `0x17`, and GPIO1 output topology;
- known codec subsystem ID `0x19e5327e`.

> [!WARNING]
> The same SN6140 model name does not guarantee identical GPIO/EAPD wiring on
> another laptop. A local build inspects the live topology. GitHub Actions has
> no codec hardware and can only perform a compile-time check for explicitly
> supplied parameters. A green CI run is not hardware validation.

## 1. Install or check build tools

Required Arch packages provide `gcc`, `make`, `curl`, `gpg`, `bsdtar`, `zstd`,
`patch`, `modinfo`, and `pacman-key`. Check commands without changing the
system:

```sh
for command in gcc make curl gpg bsdtar zstd patch modinfo pacman-key; do
  command -v "$command" >/dev/null || echo "Missing command: $command"
done
```

No output means this check passed. If a command is missing, use
`pacman -F <command>` to identify its package, review it, install it yourself,
and rerun the check. Do not run `build.sh` with sudo; elevated privileges do
not supply missing tools. The builder downloads the exact headers package into
the repository and does not require installing `linux-zen-headers` globally.

## 2. Collect and verify local parameters

Enter the repository and save a read-only baseline:

```sh
cd ~/work/repos/kernel-module-hda-sn6140
./scripts/collect-sn6140.sh report.sn6140.before.txt
```

The file is written to `reports/report.sn6140.before.txt`, never to the
repository root. Pass only a file name matching
`report.sn6140.<non-empty-label>.txt`; directory arguments are rejected.

### Kernel and package version

```sh
uname -r
pacman -Q linux-zen
modinfo -n snd_hda_codec_conexant
modinfo -F vermagic snd_hda_codec_conexant
```

If pacman was upgraded but `uname -r` still reports the old kernel, reboot into
the intended kernel and run the commands again. If they still disagree, stop
and inspect the selected boot entry. Do not build against new headers for an
old running kernel.

### Driver must be modular

```sh
zgrep '^CONFIG_SND_HDA_CODEC_CONEXANT=' /proc/config.gz
```

The result must be `CONFIG_SND_HDA_CODEC_CONEXANT=m`. With `=y`, the driver is
built into the kernel and cannot be overridden with one `.ko`; use a complete,
revertible kernel package instead. If `/proc/config.gz` is unavailable, verify
the `.config` from headers that exactly match `uname -r`. Do not install until
you can prove the setting is `m`.

### Codec and subsystem ID

```sh
grep -H -E '^(Codec|Vendor Id|Subsystem Id):' \
  /proc/asound/card*/codec#*
```

The verified hardware reports:

```text
Codec: Conexant SN6140
Vendor Id: 0x14f11f87
Subsystem Id: 0x19e5327e
```

If the codec or vendor differs, stop and retain the report for the correct
driver investigation. If only the subsystem ID differs, do not substitute the
known ID manually: first prove that the new machine has the same NID/GPIO
wiring and add a separate quirk.

### DSP endpoint split

```sh
cat /proc/asound/pcm
```

Expect separate `HDA Analog`, `DMIC`, and `DMIC16kHz` entries.

> [!WARNING]
> If DMIC is already absent before installation, this output-routing patch
> cannot create it. Stop installation and restore the correct SOF firmware,
> machine driver, and topology first.

### Module signature policy

```sh
cat /sys/module/module/parameters/sig_enforce
cat /sys/kernel/security/lockdown 2>/dev/null || true
```

The generated module is not signed with Arch's private build key. If signature
enforcement or lockdown rejects it, the scripts stop. Do not disable Secure
Boot, add `module.sig_enforce=0`, or use force-loading options. Use your own
properly enrolled trusted module-signing process if Secure Boot is required.

## 3. Build the module

Run as a normal user:

```sh
./scripts/build.sh
```

The first run downloads roughly 215 MiB of compressed source material. Verified
downloads are cached in `cache/`; a later rebuild can use:

```sh
./scripts/build.sh --offline
```

Successful output is placed under:

```text
dist/<kernel-release>/snd-hda-codec-conexant.ko
dist/<kernel-release>/snd-hda-codec-conexant.ko.zst
dist/<kernel-release>/BUILD-INFO.txt
```

A failed build installs nothing. Keep the first `ERROR` line and use the
[testing guide's failure table](docs/TESTING.md#2-build-as-an-unprivileged-user)
to distinguish missing tools, signature failure, a kernel/package mismatch,
and an unsupported codec topology. Topology failures need a new quirk, not a
force option.

## 4. Verify output before installation

```sh
kernel_release=$(uname -r)
dist_dir="dist/$kernel_release"

cat "$dist_dir/BUILD-INFO.txt"
modinfo "$dist_dir/snd-hda-codec-conexant.ko"
zstd -t "$dist_dir/snd-hda-codec-conexant.ko.zst"
```

Verify that the recorded kernel release equals `uname -r`, built and original
vermagic match exactly, vendor is `0x14f11f87`, codec subsystem ID matches the
baseline report, and `zstd -t` succeeds.

> [!CAUTION]
> Never install when kernel release, vermagic, codec ID, or topology differs.
> Renaming or recompressing a module cannot repair an ABI mismatch. Reboot into
> the correct target kernel and rebuild; never use `modprobe --force`.

## 5. Pre-install checks

```sh
./scripts/manage.sh status
```

A first installation normally reports `override_file=absent` and
`active_override=no`. If an override is already active, do not install over it;
compare its srcversion with `dist/` or roll it back first. If the file exists
but is inactive, compare its path's kernel release with `uname -r` instead of
force-loading it.

Check whether the distribution module is embedded in initramfs:

```sh
lsinitcpio -a /boot/initramfs-linux-zen.img | \
  grep -E 'snd[-_]hda[-_]codec[-_]conexant|conexant'
```

No output normally means the disk override can be selected. If output appears,
stop and identify whether the boot image is managed by mkinitcpio, dracut, or a
UKI. Back up a known-good image and learn its restore procedure before changing
it. Do not blindly rebuild initramfs when the boot chain is unknown.

## 6. Install explicitly

Close playback, recording, browser audio, and meeting software. Verify that a
known-good kernel can actually be selected from the boot menu, then run:

```sh
sudo ./scripts/manage.sh install
sudo reboot
```

The installer adds only:

```text
/usr/lib/modules/<kernel-release>/updates/sn6140/snd-hda-codec-conexant.ko.zst
```

It does not overwrite the distribution module or hot-unload the HDA/SOF module
tree. It runs `depmod` for the current release and relies on a clean reboot.

> [!CAUTION]
> This is the highest-risk step. Do not overwrite files under the distribution
> `kernel/sound/` tree, recursively remove sound modules, or force-unload an
> audio stack in use. If installation reports an error, retain the output and
> run `manage.sh status`; roll back a partially present override before retrying.

## 7. Validate after reboot

```sh
./scripts/manage.sh status
```

Expected state:

```text
selected_module=.../updates/sn6140/snd-hda-codec-conexant.ko.zst
override_file=present
active_override=yes
```

If the selected module still points to `kernel/sound/`, check that this is the
same `uname -r` used for installation and inspect `depmod -n`. Do not hot-unload
the complete sound stack; roll back if the override cannot be proven active.

Collect the after report and kernel log:

```sh
./scripts/collect-sn6140.sh report.sn6140.after.txt
journalctl -k -b | grep -Ei 'snd|sof|hda|SN6140|error|warn'
```

At low volume, test speaker playback, concurrent DMIC recording, headphone
insertion/removal at least ten times, and the same sequence after suspend and
resume. Determine the DMIC card/device from `/proc/asound/pcm`; do not guess a
device number.

> [!WARNING]
> Pops, feedback, simultaneous speaker/headphone output, total silence, codec
> timeouts, SOF IPC errors, or a disappearing DMIC are failures. Stop playback,
> retain both reports and the kernel log, and roll back immediately.

## Rollback

When the current kernel still boots:

```sh
sudo ./scripts/manage.sh rollback
sudo reboot
```

After reboot, status should report `override_file=absent`,
`active_override=no`, and select the distribution module under
`kernel/sound/hda/codecs/`. If it remains present, compare the reported path
with `uname -r`; do not delete a broad module directory.

If the affected kernel cannot boot, select the known-good kernel, identify the
exact affected release, remove only its
`updates/sn6140/snd-hda-codec-conexant.ko.zst`, and run
`sudo depmod <affected-release>`.

> [!CAUTION]
> Never remove all of `/usr/lib/modules`, an entire kernel-release directory,
> or the distribution module under `kernel/sound/hda/codecs/`. If the affected
> release cannot be identified unambiguously, preserve the system and ask for
> help instead of using a recursive deletion command.

## GitHub Actions

`.github/workflows/build-module.yml` runs on pushes to `main`, pull-request
`synchronize` and `ready_for_review` events, and manual `workflow_dispatch`.
Manual overrides require all three values together: Arch package version,
exact kernel release, and codec subsystem ID. The workflow uploads the module,
compressed module, `BUILD-INFO.txt`, and `SHA256SUMS` for seven days.

CI cannot inspect real NIDs, GPIO, EAPD, or audio behavior. Downloaded CI output
must still pass the local checks above before installation.

## License

Unless a file states otherwise, the repository is licensed under GNU GPL
version 2 or later. The kernel patch retains the `GPL-2.0-or-later` license of
the modified Linux source. See [COPYING](COPYING).
