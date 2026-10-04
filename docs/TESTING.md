# Testing

[简体中文](TESTING.zh-CN.md) · [Home](../README.md)

## Audio

After reboot, run `sn6140 status`. Confirm the module is under `updates/dkms/`
and the loaded version matches. Play audio at low volume and check:

- Speakers play without headphones, mute on insertion and resume on removal.
- Switching still works after ten insertion/removal cycles.
- Recording the internal microphone during playback interrupts neither stream.
- All checks still pass after suspend/resume.

Find the recording device in the DMIC entries of `cat /proc/asound/pcm`.
Stop testing if there are loud pops, simultaneous outputs or a missing microphone;
roll back using the [maintenance guide](ARCH.md).

Collect state before and after installation for comparison:

```sh
./scripts/collect-sn6140.sh report.sn6140.before.txt
./scripts/collect-sn6140.sh report.sn6140.after.txt
journalctl -k -b | grep -Ei 'snd|sof|hda|SN6140|error|warn'
```

Reports stay in local `reports/`, excluded from Git.

## Development checks

```sh
make check
make package
./tests/dkms-sandbox.sh
```

`make check` covers syntax and environment detection. The sandbox test requires
bubblewrap, matching headers, the original distribution module and supported
live hardware. It exercises DKMS builds, legacy conflicts, pacman hook installation
and original-module restoration in isolated directories, without loading modules
or updating boot images.

## Compile a module separately

`./scripts/build.sh` targets the running kernel and writes to `dist/$(uname -r)/`.
`BUILD-INFO.txt` records input versions and vermagic. Add `--offline` when the
cache is complete. Use the README's DKMS package workflow for installation.

CI targets are configured in `.github/targets.env`; CI checks compilation only.
