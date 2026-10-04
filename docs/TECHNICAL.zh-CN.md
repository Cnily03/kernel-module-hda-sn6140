# 实现

[English](TECHNICAL.md) · [首页](../README.zh-CN.md)

## 输出路由

CREF-XX 的 SN6140 有三项耦合控制：NID `0x16` 的耳机选择器同时影响扬声器，
NID `0x17` 的 EAPD 控制功放，GPIO1 控制耳机通路。

补丁为 `conexant.c` 注册 automute hook，在通用静音处理后统一设置这三项，
并在初始化和恢复时重设路由。SOF、DSP topology 和 DMIC PCM 保持原样。
构建时将 RFC patch 的 PCI 匹配改为 codec SSID `19e5:327e`。

## 构建与更新

Conexant 依赖 Arch headers 未提供的 HDA 私有头文件和 helper 源码，因此每次
构建都获取目标版本的 Linux 源码和 Zen patch，而非一直复用某版驱动源码。

`scripts/build.sh` 以固定指纹验签，依次应用 Zen 和 SN6140 补丁，再使用目标
headers 编译。检查项包括包版本、`Module.symvers`、GCC 和 vermagic；
缺少 pahole 时跳过可选 BTF。

`70-dkms-install.hook` 传入新安装的内核版本，不依赖 `uname -r`。
安装前检查本机 codec、DMIC 和旧模块冲突；DKMS 负责签名、安装与 depmod，
标准 `90-mkinitcpio-install.hook` 随后更新启动镜像。

## 限制

- 版本格式目前支持 `X.Y.Z.zenN-pkgrel`。
- 源码按“上游 Linux + Zen patch”还原，未重放 Arch 的所有下游补丁。
- 安装检查依赖 `/proc/asound`；未暴露声卡的 chroot 无法通过。
- DKMS 签名证书仍需受内核信任；未来内核接口变化可能需要更新补丁。

参考：[Arch DKMS](https://wiki.archlinux.org/title/Dynamic_Kernel_Module_Support)、
[DKMS 手册](https://man.archlinux.org/man/extra/dkms/dkms.8.en)。
