# SN6140 声卡修复

[简体中文](README.zh-CN.md) | [English](README.md)

修复 Huawei MateBook 16s（CREF-XX/M1010）在 Linux 下的扬声器无声和耳机切换异常。
通过 Arch DKMS 软件包安装，随 `linux-zen` 更新自动重建驱动，无需手填内核版本或声卡参数。
只构建 Conexant 驱动模块，保留 SOF 和内置数字麦克风。

支持 **Arch Linux x86_64 + linux-zen**，适用于 SN6140 `14f1:1f87 / 19e5:327e`。
修复仍属实验性，首次测试请降低音量并保留备用内核。

## 安装

安装依赖：

```sh
sudo pacman -Syu --needed base-devel dkms linux-zen linux-zen-headers \
  curl gnupg libarchive patch kmod xz zstd
```

在仓库目录检查环境、构建并安装软件包：

```sh
make doctor
make package
sudo pacman -U dist/packages/sn6140-linux-zen-dkms-0.2.0-1-x86_64.pkg.tar.zst
```

安装过程中会下载、验签并编译目标内核的驱动，需联网及数 GiB 临时空间。
等待 DKMS 和启动镜像更新成功后重启，再检查：

```sh
sn6140 status
```

模块路径应位于 `updates/dkms/`，已加载模块应与之匹配。

## 更新与卸载

正常执行 `sudo pacman -Syu` 即可自动重建。保持 `linux-zen-headers` 已安装，
无需每次重新打包。构建失败、Secure Boot 或自定义启动镜像问题见[维护指南](docs/ARCH.zh-CN.md)。

卸载并恢复原驱动：

```sh
sudo pacman -R sn6140-linux-zen-dkms
sudo reboot
```

## 文档

- [安装维护与故障处理](docs/ARCH.zh-CN.md)
- [修复原理与构建设计](docs/TECHNICAL.zh-CN.md)
- [测试](docs/TESTING.zh-CN.md)

许可证：[GPL-2.0-or-later](COPYING)。
