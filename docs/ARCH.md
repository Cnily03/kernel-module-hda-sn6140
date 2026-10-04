# Maintenance

[简体中文](ARCH.zh-CN.md) · [Home](../README.md)

## Failed updates

Check `sn6140 status` and the `make.log` path printed by DKMS.
A failed build hook does not undo the kernel upgrade. Resolve it before rebooting.

| Error | Action |
| --- | --- |
| `Manual override exists` | Remove the target kernel's old manual module |
| Missing or mismatched headers | Install `linux-zen-headers` matching `linux-zen` |
| Download or signature failure | Check network, clock and cache; retain failed files and keep verification enabled |
| `Compiler mismatch` | Compare GCC with the target kernel's compiler version |
| Patch or build failure | Keep logs and use a fallback kernel until the patch is updated |
| `Key was rejected` | Check whether the kernel trusts the DKMS signing certificate |
| Installed but not loaded | Check the booted kernel and initramfs/UKI |

After resolving the cause, retry:

```sh
target=$(pacman -Qlq linux-zen | sed -n 's|^/usr/lib/modules/\([^/]*\)/pkgbase$|\1|p')
version=$(pacman -Q sn6140-linux-zen-dkms | awk '{print $2}')
sudo dkms install -m sn6140 -v "${version%-*}" -k "$target"
```

After a manual retry, run `sudo mkinitcpio -P` for mkinitcpio, or regenerate
images with your dracut/custom UKI setup. Normal pacman updates use system hooks.

## Restore the original driver

Run `sudo pacman -R sn6140-linux-zen-dkms`, then reboot.
DKMS restores the original module saved under `/var/lib/dkms/sn6140/`;
do not delete that directory directly. Downloads remain in `/var/cache/sn6140/`.

If the target kernel cannot boot, use a fallback kernel or installation media
to remove the package and regenerate boot images. Reinstall the corresponding
`linux-zen` package if the original-module backup is missing.
