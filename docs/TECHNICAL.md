# Implementation

[简体中文](TECHNICAL.zh-CN.md) · [Home](../README.md)

## Output routing

CREF-XX's SN6140 couples three controls: the headphone selector at NID `0x16`
also affects speakers, NID `0x17` EAPD controls the amplifier, and GPIO1 gates
headphones.

The patch adds an automute hook to `conexant.c`, updating all three after generic
mute handling and reapplying the route on initialization/resume. SOF, DSP
topology and DMIC PCMs stay unchanged. The builder converts the RFC patch's
PCI match to codec SSID `19e5:327e`.

## Builds and updates

Conexant needs private HDA headers and helper sources missing from Arch's
headers package. Each build therefore fetches the target version's Linux
sources and Zen patch rather than reusing an old driver snapshot.

`scripts/build.sh` verifies pinned signer fingerprints, applies Zen and SN6140
patches, then compiles against the target headers. It checks package versions,
`Module.symvers`, GCC and vermagic. Optional BTF is skipped without pahole.

`70-dkms-install.hook` supplies the newly installed kernel release independently
of `uname -r`. Pre-install checks cover the live codec, DMIC and old overrides.
DKMS handles signing, installation and depmod; standard
`90-mkinitcpio-install.hook` then updates boot images.

## Limitations

- Version parsing currently accepts `X.Y.Z.zenN-pkgrel`.
- Sources reproduce upstream Linux plus Zen, not every downstream Arch patch.
- Installation checks require `/proc/asound`; chroots without audio hardware fail.
- The kernel must trust the DKMS signing certificate. Future kernel interfaces
  may require patch updates.

References: [Arch DKMS](https://wiki.archlinux.org/title/Dynamic_Kernel_Module_Support),
[DKMS manual](https://man.archlinux.org/man/extra/dkms/dkms.8.en).
