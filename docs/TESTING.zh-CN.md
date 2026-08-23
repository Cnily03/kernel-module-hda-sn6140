# SN6140 构建、试验与回滚指南

[简体中文](TESTING.zh-CN.md) | [English](TESTING.md) | [返回主页](../README.zh-CN.md)

这份文档面向第一次测试内核模块的用户。过程分为三段：

1. 只读收集和构建：使用普通用户，不修改系统；
2. 安装与重启：明确使用 `sudo`，在当前内核中新增 override；
3. 功能验证与回滚：检查扬声器、耳机和 DMIC 是否仍能分开工作。

> [!CAUTION]
> 安装前必须保留一个可从启动菜单进入的未修改内核。如果你不知道
> 当前启动器如何选择其他内核，请停在构建阶段；模块已经生成也不必
> 立即安装。

## 0. 开始前的快速检查

在仓库根目录运行：

```sh
uname -r
pacman -Q linux-zen
zgrep '^CONFIG_SND_HDA_CODEC_CONEXANT=' /proc/config.gz
```

只有同时满足下列条件才继续：当前运行 `linux-zen`，pacman 中存在与它
对应的包，并且配置输出为 `CONFIG_SND_HDA_CODEC_CONEXANT=m`。

| 检查失败 | 意味着什么 | 应该怎么做 |
| --- | --- | --- |
| pacman 版本已升级，`uname -r` 还是旧版 | 磁盘内核与运行中内核不一致 | 重启进入新内核后重新检查；不要混用 headers |
| 配置为 `=y` | Conexant 驱动已编进内核 | 停止单 `.ko` 方案，改用完整内核补丁和可回退的内核包 |
| `/proc/config.gz` 不存在 | 无法从当前内核读配置 | 从与 `uname -r` 精确对应的 headers 核对 `.config`；无法证明是 `m` 时不安装 |
| 不是 Arch `linux-zen` | 自动下载和 ABI 验证路径不适用 | 不要伪造版本参数；先为该发行版补充构建支持 |

## 1. 保存安装前基线

```sh
./scripts/collect-sn6140.sh report.sn6140.before.txt
./scripts/manage.sh status
```

报告会写入 `reports/report.sn6140.before.txt`。它只读取硬件和内核状态，不会录音、
加载模块或修改 mixer。用下面的命令提取关键行：

```sh
grep -E 'Codec:|Vendor Id:|Subsystem Id:|Node 0x16|Node 0x17|IO\[1\]|HDA Analog|DMIC' \
  reports/report.sn6140.before.txt
```

已支持的基线应包含 SN6140、vendor `0x14f11f87`、耳机 NID `0x16`、扬声器
NID `0x17`、GPIO1，以及分开的 `HDA Analog`、`DMIC`、`DMIC16kHz`。

> [!WARNING]
> codec/vendor 不一致时，这不是本补丁的目标硬件，不要安装。NID/GPIO
> 不一致时，保留报告并为该机型分析新 quirk，不要绕过拓扑检查。
> 如果只是 DMIC 缺失，先恢复 SOF 固件、machine driver 和 topology；这个输出
> 补丁不能创建消失的 DSP 端点。

## 2. 以普通用户构建

```sh
./scripts/build.sh
```

首次构建会下载精确版本的 headers、Linux 源码和 Zen 补丁，并先验证签名。
成功产物位于 `dist/$(uname -r)/`。

| 构建失败 | 处理方法 |
| --- | --- |
| 缺少 `gcc`、`gpg`、`bsdtar`、`zstd` | 用 README 的依赖检查命令找出缺失工具，审阅后自行通过 pacman 安装并重试 |
| 下载或 GPG 验签失败 | 检查系统时间和 `archlinux-keyring`；不使用未验证文件，网络恢复后重试 |
| package version 与 `uname -r` 不符 | 重启到与已安装包一致的内核，再从头构建 |
| topology/SSID 检查失败 | 保留 `reports/` 中的基线报告并停止安装；该硬件需要单独的 quirk |
| 权限错误 | 检查仓库是否曾被 sudo 写成 root 所有；修复所有者后仍以普通用户构建 |

下载缓存已完整时，可用 `./scripts/build.sh --offline` 重建。如果它报缓存
缺失，取消 `--offline` 并在网络恢复后重试。

## 3. 验证构建产物

```sh
kernel_release=$(uname -r)
dist_dir="dist/$kernel_release"
cat "$dist_dir/BUILD-INFO.txt"
modinfo "$dist_dir/snd-hda-codec-conexant.ko"
zstd -t "$dist_dir/snd-hda-codec-conexant.ko.zst"
```

必须核对：`kernel_release` 等于 `uname -r`，`built_vermagic` 等于
`original_vermagic`，vendor 为 `0x14f11f87`，SSID 与基线报告相同，且 `zstd -t`
成功。

> [!WARNING]
> 任何一项不一致都不能通过改名、重新压缩或 `modprobe --force` 修复。
> 放弃该次 `dist/<kernel-release>/` 产物，重启到正确的目标内核后重新构建。
> SSID 或拓扑不同时，需要新的硬件 quirk，重复构建不会改变结果。

## 4. 检查 initramfs

```sh
lsinitcpio -a /boot/initramfs-linux-zen.img | \
  grep -E 'snd[-_]hda[-_]codec[-_]conexant|conexant'
```

- 没有输出：可继续，模块将从磁盘上的 `updates/sn6140/` 选取；
- 有输出：暂停安装，旧模块可能在根文件系统挂载前就被加载。

有输出时，先确定 initramfs 由 mkinitcpio、dracut 还是 UKI 生成，并备份当前可启动
镜像。在不知道如何恢复原镜像时，不要重建 initramfs，只保留 `dist/` 产物。

## 5. 安装（从这里开始修改系统）

```sh
./scripts/manage.sh status
```

首次安装通常应看到 `override_file=absent` 和 `active_override=no`。

- `override_file=present` 且 `active_override=yes`：补丁已经生效，不要重复安装；先比较
  `srcversion` 和 `dist/` 中的模块，或回滚后重来；
- `override_file=present` 但 `active_override=no`：通常是尚未重启，或当前 kernel release
  不同。核对 `uname -r` 和 override 路径；不一致时不要强制加载。

关闭播放、录音、会议和浏览器音频页面，把音量降低，然后执行：

```sh
sudo ./scripts/manage.sh install
sudo reboot
```

安装器只在 `/usr/lib/modules/$(uname -r)/updates/sn6140/` 下新增模块并运行 `depmod`；
不覆盖发行版原模块，也不热卸载 HDA/SOF。

> [!WARNING]
> 安装报错时不要手工复制 `.ko`、覆盖 `kernel/sound/` 下的原文件或使用
> `modprobe --force`。保留错误输出，再运行 `./scripts/manage.sh status`。如果 override
> 仍是 absent，系统尚未安装它；修复报错原因后再重试。

## 6. 重启后验证

### 6.1 证明 override 真正加载

```sh
./scripts/manage.sh status
```

成功状态：

```text
selected_module=.../updates/sn6140/snd-hda-codec-conexant.ko.zst
override_file=present
active_override=yes
```

如果 `selected_module` 仍指向 `kernel/sound/`，检查是否重启到安装时的同一
`uname -r`，再查看 `depmod -n "$(uname -r)" | grep snd-hda-codec-conexant`。不要热卸载
整棵声卡模块；无法证明 override 被选中时，直接回滚。

```sh
./scripts/collect-sn6140.sh report.sn6140.after.txt
journalctl -k -b | grep -Ei 'snd|sof|hda|SN6140|error|warn'
```

新报告位于 `reports/report.sn6140.after.txt`。

### 6.2 低音量并行播放与录音

终端 A：

```sh
speaker-test -D hw:sofhdadsp,0 -c 2 -r 48000 -t sine
```

终端 B：先从 `/proc/asound/pcm` 找到 DMIC device，下面的 `6` 只是示例。

```sh
arecord -D hw:sofhdadsp,6 -f S16_LE -r 48000 -c 4 \
  -d 10 /tmp/sn6140-dmic.wav
aplay /tmp/sn6140-dmic.wav
```

如果 `arecord` 显示设备不存在，不要猜数字；重新查看 `/proc/asound/pcm` 中 DMIC
的 card/device。如果 DMIC 条目已消失，保留内核日志并回滚。

成功标准是播放不占用或切断 DMIC，录音开始/停止也不切断扬声器。

### 6.3 耳机插拔和休眠

低音量持续播放时依次验证：

1. 未插耳机时仅扬声器发声；
2. 插入后扬声器停止、耳机发声；
3. 拔出后耳机停止、扬声器恢复；
4. 重复至少十次；
5. suspend/resume 后重复；
6. 每种输出状态再进行一次 DMIC 录音。

> [!CAUTION]
> 爆音、啸叫、两路同时发声、全部静音、codec timeout、SOF IPC error 或 DMIC
> 消失都属于失败。立即停止播放，保留 `reports/` 中的 before/after 报告和
> `journalctl` 输出，然后回滚；不要继续插拔寻找「偶然可用」的状态。

## 7. 回滚

仍能进入当前内核时：

```sh
sudo ./scripts/manage.sh rollback
sudo reboot
```

重启后的 `./scripts/manage.sh status` 应显示 `override_file=absent`、
`active_override=no`，且 `selected_module` 回到 `kernel/sound/hda/codecs/`。如果 override
仍存在，不要反复重启；核对回滚命令报告的路径与当前 `uname -r`。

如果故障内核无法正常启动：

1. 从启动菜单进入之前保留的其他内核；
2. 确定故障内核的完整 release；
3. 只删除该 release 下的 `updates/sn6140/snd-hda-codec-conexant.ko.zst`；
4. 运行 `sudo depmod <故障内核 release>` 后再启动验证。

> [!CAUTION]
> 不要删除整个 `/usr/lib/modules`、整个 kernel release 目录，或发行版位于
> `kernel/sound/hda/codecs/` 的原模块。无法唯一确定故障 release 时，先保留
> 现状并寻求协助，不要使用递归删除命令。
