# kernel-module-hda-sn6140

[简体中文](README.zh-CN.md) | [English](README.md)

为 Huawei MateBook 16s `CREF-XX/M1010` 上的 Conexant SN6140 声卡提供一个
实验性 Linux 内核驱动修复。本仓库不会完整编译或替换内核，而是根据目标
Arch `linux-zen` 精确生成一个可单独测试的
`snd-hda-codec-conexant.ko`。

> [!CAUTION]
> 这个补丁会直接控制声卡 codec 的连接选择器、EAPD 和 GPIO1。错误的硬件
> 匹配或切换顺序可能产生爆音、扬声器/耳机同时发声，甚至让输出持续静音。
> 第一次测试必须降低音量，并保留一个未修改、可从启动菜单进入的备用内核。
> 不要把为另一个 kernel release 生成的 `.ko` 安装到当前内核。

## 怎样使用这份文档

只想了解原理时，先阅读「这个仓库解决什么问题」和「它如何修复」。准备
实际测试时，按本页第一步到第七步依次操作，不要跳过参数和 initramfs
检查。需要逐项记录结果时，使用
[`docs/TESTING.zh-CN.md`](docs/TESTING.zh-CN.md)；它为常见失败提供了停止、修复或回滚方法。

> [!IMPORTANT]
> 「检查失败」不代表应该用 `--force`、sudo 或手工复制模块绕过。
> 它通常表示内核、已安装包、codec 拓扑或签名策略与假设不一致。保留
> 错误输出和 `reports/` 中的报告，按对应步骤的失败说明处理。

## 这个仓库解决什么问题

这台机器在 Linux 下并不是简单地「缺少一张声卡」。Intel SOF/DSP 通常已经
把音频端点分成：

- `HDA Analog`：扬声器、耳机和耳麦口模拟输入；
- `DMIC`：内置数字麦克风阵列；
- `DMIC16kHz`：低采样率数字麦克风端点；
- HDMI/DisplayPort 数字输出。

真正异常的是 SN6140 的模拟输出布线。已观察到的 CREF-XX 硬件中：

- 耳机 pin 是 NID `0x16`；
- 内置扬声器 pin 是 NID `0x17`；
- NID `0x16` 的连接选择器也会影响扬声器路径；
- NID `0x17` 的 EAPD 控制外部功放；
- GPIO1 额外控制耳机路径。

Linux 通用 Conexant HDA automute 并不知道这几项是耦合的。它按普通声卡分别
处理扬声器与耳机，所以可能出现：

- 未插耳机时扬声器无声；
- 插入耳机后仍从扬声器播放，或耳机无声；
- 反复插拔后输出路径颠倒或全部静音；
- 使用用户态 HDA verb 临时修复时，音频会在重启、休眠或插拔后失效；
- 输出路径切换与录音同时进行时，表面上看起来像「麦克风和扬声器冲突」。

## 它如何修复

补丁修改内核的 `sound/hda/codecs/conexant.c`，为匹配的 SN6140 注册专用
automute hook。每次耳机状态或主静音状态变化时，它先保留内核原有的通用
HDA 处理，再统一设置：

1. NID `0x16` 的连接选择器；
2. NID `0x17` 的 EAPD；
3. GPIO1 的方向、掩码和输出值。

补丁不修改 SOF machine driver、DSP topology 或 DMIC PCM，因此内置数字
麦克风仍由 DSP 独立暴露。修复目标是输出路由，不是用 legacy HDA 替换 SOF。

构建器还会根据正在运行的内核完成这些保护：

- 找到当前模块所属的精确 Arch 包版本，而不是只猜一个相近源码版本；
- 下载并验签完全对应的 `linux-zen-headers`、Linux 源码和 Zen patch；
- 使用 headers 中的 `.config`、`Module.symvers`、`utsrelease.h` 和
  `compile.h`；
- 比较 GCC 与最终模块 vermagic；
- 自动读取 SN6140 codec subsystem ID；
- 在本机模式下检查 NID `0x16/0x17`、双路 selector 和 GPIO1 拓扑；
- 只编译 `snd-hda-codec-conexant.ko`，不完整编译内核。

> [!NOTE]
> `scripts/build.sh` 只负责构建，不会执行 sudo、
> 安装模块或修改 `/boot`、`/etc`。

## 支持范围

目前自动构建路径支持：

- Arch Linux x86_64；
- `linux-zen`；
- `CONFIG_SND_HDA_CODEC_CONEXANT=m`；
- Conexant SN6140 codec vendor ID `0x14f11f87`；
- 已验证拓扑：耳机 NID `0x16`、扬声器 NID `0x17`、GPIO1 输出；
- 已知 codec subsystem ID `0x19e5327e`。

> [!WARNING]
> 「同样叫 SN6140」不代表笔记本厂商采用了相同 GPIO/EAPD 布线。本机构建器
> 会验证拓扑；GitHub Actions 没有真实声卡，只能对明确提供的参数进行编译
> 检查。不要把 Actions 成功理解成另一台电脑已经完成硬件兼容验证。

## 第一步：安装构建工具

需要以下 Arch 软件包提供的工具：

- `base-devel`：GCC、make 等基础编译工具；
- `curl`、`gnupg`、`libarchive`、`zstd`、`patch`；
- `pacman`/`pacman-key`、`kmod`。

查看缺少哪些命令：

```sh
for command in gcc make curl gpg bsdtar zstd patch modinfo pacman-key; do
  command -v "$command" >/dev/null || echo "缺少命令: $command"
done
```

仓库本身不会替你安装系统软件包。请审阅后自行通过 pacman 安装缺少的工具。
不需要把 `linux-zen-headers` 安装到宿主系统，构建器会下载精确版本并解包到
仓库临时目录。

没有输出「缺少命令」即表示这项检查通过。如果列出了缺失项，先用
`pacman -F <命令名>` 确认它属于哪个 Arch 包，安装后重新检查。不要改用
sudo 运行 `build.sh`；提高权限不能补齐构建工具。

## 第二步：获取并核对硬件参数

进入仓库：

```sh
cd ~/work/repos/kernel-module-hda-sn6140
```

先生成只读报告：

```sh
./scripts/collect-sn6140.sh report.sn6140.before.txt
```

报告实际写入 `reports/report.sn6140.before.txt`，不会散落在仓库根目录。
如果脚本提示文件名不符合格式，只传入
`report.sn6140.<非空标识>.txt`，不要携带目录部分。

### 1. 内核与包版本

```sh
uname -r
pacman -Q linux-zen
modinfo -n snd_hda_codec_conexant
modinfo -F vermagic snd_hda_codec_conexant
```

已验证基线示例：

```text
uname -r:     7.1.8-zen1-3-zen
Arch package: linux-zen 7.1.8.zen1-3
```

如果已经安装过本仓库 override，`modinfo -n` 可能指向
`updates/sn6140/`。构建器会继续寻找 pacman 拥有的发行版原模块来确定版本，
不要求先删除 override。

> [!WARNING]
> 如果刚升级 `linux-zen` 但还没有重启，`pacman -Q linux-zen` 和
> `uname -r` 可能属于不同内核。先重启进入准备测试的内核，再重新运行
> 这组命令。重启后仍不一致时，停止构建并检查启动菜单是否选中了新内核。

### 2. 驱动必须是模块

```sh
zgrep '^CONFIG_SND_HDA_CODEC_CONEXANT=' /proc/config.gz
```

必须得到：

```text
CONFIG_SND_HDA_CODEC_CONEXANT=m
```

如果是 `=y`，Conexant 驱动已经编进内核，不能通过替换单个 `.ko` 修复，只能
使用完整内核补丁方案。如果命令没有输出，先从与当前 kernel release
精确对应的 headers `.config` 核对；无法证明是 `m` 时不要安装。

### 3. Codec ID 与 subsystem ID

```sh
grep -H -E '^(Codec|Vendor Id|Subsystem Id):' \
  /proc/asound/card*/codec#*
```

目标 codec 应至少显示：

```text
Codec: Conexant SN6140
Vendor Id: 0x14f11f87
Subsystem Id: 0x19e5327e
```

`0x19e5327e` 可拆成 codec subvendor `19e5` 和 subdevice `327e`。最终模块使用
codec SSID 生成 `HDA_CODEC_QUIRK`，不再固定依赖 HDA 控制器的 PCI subsystem
`19e5:3e5f`。

没有找到 SN6140，或 vendor ID 不是 `0x14f11f87` 时，不要安装这个模块。
保留报告并为实际 codec 查找对应驱动。只有 subsystem ID 不同时也不要手工
写入已知 ID；需先证明新机器具有相同 NID/GPIO 布线，再添加 quirk。

### 4. 输入输出是否由 DSP 分开枚举

```sh
cat /proc/asound/pcm
```

应能分别看到类似：

```text
HDA Analog ... playback 1 : capture 1
DMIC ... capture 1
DMIC16kHz ... capture 1
```

> [!WARNING]
> 如果 DMIC 在安装补丁前就不存在，或系统正在使用 legacy HDA 而不是 SOF，
> 本补丁不会凭空创建 DSP 麦克风端点。不要继续安装；先恢复正确的 SOF 固件、
> machine driver 与 topology。

### 5. 模块签名策略

```sh
cat /sys/module/module/parameters/sig_enforce
cat /sys/kernel/security/lockdown 2>/dev/null || true
```

当前已验证机器为 `sig_enforce=N` 且 lockdown 选择 `[none]`。本地生成的模块
没有 Arch 的私有签名密钥；若系统强制签名或 lockdown 生效，构建/管理脚本会
拒绝继续。

> [!WARNING]
> 不要为了加载本模块而关闭 Secure Boot、添加 `module.sig_enforce=0`、使用
> `--force` 或绕过内核签名检查。需要 Secure Boot 时，应使用你自己受信任并
> 已正确注册的模块签名流程。

## 第三步：构建模块

以普通用户运行：

```sh
./scripts/build.sh
```

也可以使用：

```sh
make build
```

第一次会下载约 215 MiB 压缩文件，并在解包时临时占用更多空间。所有上游
文件都会先验证签名。缓存位于 `cache/`；之后可以离线重建：

```sh
./scripts/build.sh --offline
```

查看所有参数：

```sh
./scripts/build.sh --help
```

成功后文件位于：

```text
dist/<uname -r>/snd-hda-codec-conexant.ko
dist/<uname -r>/snd-hda-codec-conexant.ko.zst
dist/<uname -r>/BUILD-INFO.txt
```

构建失败时不会安装任何系统文件。保留终端中第一条 `ERROR`，按
[测试指南的构建失败表](docs/TESTING.zh-CN.md#2-以普通用户构建)区分缺失工具、
验签失败、内核版本错位和硬件拓扑不符。只有前三类修复后适合重试；
拓扑不符时应停止安装并分析新 quirk。

## 第四步：验证构建产物

```sh
kernel_release=$(uname -r)
artifact_dir="dist/$kernel_release"

cat "$artifact_dir/BUILD-INFO.txt"
modinfo "$artifact_dir/snd-hda-codec-conexant.ko"
zstd -t "$artifact_dir/snd-hda-codec-conexant.ko.zst"
sha256sum "$artifact_dir/snd-hda-codec-conexant.ko" \
  "$artifact_dir/snd-hda-codec-conexant.ko.zst"
```

重点核对：

- `kernel_package_version` 是准备测试的内核包版本；
- `built_vermagic` 与当前发行版模块 vermagic 完全相同；
- `codec_vendor=0x14f11f87`；
- `codec_subsystem_id` 与 codec dump 相同；
- `quirk_match=codec_ssid:<subvendor>:<subdevice>`；
- `module_signer=unsigned` 符合预期。

一条命令比较 vermagic：

```sh
test "$(modinfo -F vermagic "$artifact_dir/snd-hda-codec-conexant.ko")" = \
     "$(modinfo -F vermagic snd_hda_codec_conexant)" \
  && echo 'vermagic 匹配'
```

> [!CAUTION]
> vermagic、kernel release 或 codec 参数只要有一项不匹配，就不要安装。
> 改名或重新压缩 `.ko` 不能修复 ABI 不匹配；必须在目标内核实际运行时重新
> 构建。

## 第五步：安装前检查

查看当前状态：

```sh
./scripts/manage.sh status
```

第一次安装前通常应显示：

```text
override_file=absent
active_override=no
```

如果 `override_file=present`，说明已有测试模块。`active_override=yes` 时不要重复
安装；先比较已加载模块与 `dist/` 产物的 `srcversion`，或回滚后重新开始。
`active_override=no` 时先核对 override 路径中的 release 与 `uname -r`；不一致时
不要强制加载。

确认 initramfs 是否已经包含发行版 Conexant 模块：

```sh
lsinitcpio -a /boot/initramfs-linux-zen.img | \
  grep -E 'snd[-_]hda[-_]codec[-_]conexant|conexant'
```

没有输出时，本机通常不需要重建 initramfs。如果有输出，先停止并根据当前
启动方案制定 initramfs 备份和重建步骤；磁盘上的 `updates/` 不一定能覆盖
已经装入 initramfs 的旧模块。

有输出却不确定启动链时，安全的处理是停在这里，保留 `dist/` 产物，
先查明当前使用 mkinitcpio、dracut 还是 UKI，并学会恢复原镜像。不要在
没有备份时盲目重建 initramfs。

## 第六步：显式安装

关闭播放、录音和会议软件，确认启动菜单中存在可用备用内核，然后执行：

```sh
sudo ./scripts/manage.sh install
sudo reboot
```

如果不能实际从启动菜单选中另一个内核，不要执行 install。先安排可回退
内核并完成一次启动验证；仅看到 `/boot` 中有另一个文件不等于已验证
启动菜单可用。

安装器只新增：

```text
/usr/lib/modules/<uname -r>/updates/sn6140/snd-hda-codec-conexant.ko.zst
```

它不会覆盖发行版位于 `kernel/sound/hda/codecs/` 的原模块。安装后运行当前
内核的 `depmod`，但不会在正在使用的图形会话中热卸载 SOF/HDA 模块树。

> [!CAUTION]
> 这是风险最高的一步。不要手工覆盖发行版 `.ko`，不要删除
> `/usr/lib/modules/<版本>/kernel/` 下的原模块，也不要在有音频程序占用时
> 强制 `modprobe -r`。应通过重启让新模块干净地加载；第一次播放前把音量
> 降到较低水平。

安装命令报错时，不要手工复制产物。重新运行 `./scripts/manage.sh status`：
如果 `override_file=absent`，表示尚未安装，修复原始错误后可重试；如果已经
present，先执行 rollback 回到已知状态，不要在半完成状态上继续。

## 第七步：重启后测试

先确认 override 已生效：

```sh
./scripts/manage.sh status
```

预期：

```text
selected_module=.../updates/sn6140/snd-hda-codec-conexant.ko.zst
override_file=present
active_override=yes
```

重新采集报告与日志：

```sh
./scripts/collect-sn6140.sh report.sn6140.after.txt
journalctl -k -b | grep -Ei 'snd|sof|hda|SN6140|error|warn'
```

新报告位于 `reports/report.sn6140.after.txt`。如果 `active_override` 不是 `yes`，
说明尚未在测试新模块；不要继续音频测试，按测试指南核对 `uname -r`、
`depmod` 选择和 initramfs，无法确定时直接回滚。

低音量播放：

```sh
speaker-test -D hw:sofhdadsp,0 -c 2 -r 48000 -t sine
```

另一个终端同时录制 DMIC。下面的 device `6` 只是已验证机器的示例，必须以
当前 `/proc/asound/pcm` 为准：

```sh
arecord -D hw:sofhdadsp,6 -f S16_LE -r 48000 -c 4 \
  -d 10 /tmp/sn6140-dmic.wav
aplay /tmp/sn6140-dmic.wav
```

然后验证：

1. 未插耳机时只有内置扬声器发声；
2. 插入耳机后扬声器停止、耳机发声；
3. 拔出耳机后扬声器恢复；
4. 连续插拔至少十次；
5. suspend/resume 后重复；
6. 每种输出状态下 DMIC 都能独立录音。

> [!WARNING]
> 出现爆音、啸叫、两路同时发声、全部静音、codec timeout、SOF IPC error
> 或 DMIC 消失，都视为失败。立即停止播放，保留 before/after 报告和
> `journalctl` 输出，再按下一节回滚。不要继续插拔寻找「偶然可用」的状态。

## 回滚

仍能正常进入当前内核时：

```sh
sudo ./scripts/manage.sh rollback
sudo reboot
```

回滚只删除 `updates/sn6140` 中由本仓库安装的文件并重新运行 `depmod`。发行版
原模块从未被覆盖，重启后会自动恢复。之后检查：

```sh
./scripts/manage.sh status
```

预期 `override_file=absent`、`active_override=no`，`selected_module` 回到
`kernel/sound/hda/codecs/`。

如果回滚后 override 仍然 present，先比较管理脚本输出的路径与 `uname -r`，不要
反复重启或删除整个模块目录。路径属于另一个 release 时，从可用备用内核
按下面的应急步骤处理那个精确 release。

如果故障内核无法正常启动，先从启动菜单进入保留的其他内核，再删除故障内核
目录下精确的 `updates/sn6140/snd-hda-codec-conexant.ko.zst`，并运行
`depmod <故障内核 release>`。

> [!CAUTION]
> 应急回滚时不要删除整个 `/usr/lib/modules`、整个 kernel release 目录，或
> `kernel/sound/hda/codecs/` 下的发行版原模块。无法唯一确定故障 release
> 时，先保留现状并寻求协助，不要使用递归删除命令。

## GitHub Actions 构建

[`build-module.yml`](.github/workflows/build-module.yml) 会在
push 到 `main`、pull request 同步新提交（`synchronize`）、草稿 pull request
标记为可审阅（`ready_for_review`），以及手工 `workflow_dispatch` 时构建。
默认参数在
[`.github/targets.env`](.github/targets.env)：

```text
TARGET_PACKAGE_VERSION=7.1.8.zen1-3
TARGET_KERNEL_RELEASE=7.1.8-zen1-3-zen
TARGET_CODEC_SUBSYSTEM_ID=0x19e5327e
```

本机获取这三个值：

```sh
pacman -Q linux-zen
uname -r
grep -H -E '^(Codec|Subsystem Id):' /proc/asound/card*/codec#*
```

手工运行 workflow 时，三个输入必须一起提供。Actions 会上传：

```text
snd-hda-codec-conexant.ko
snd-hda-codec-conexant.ko.zst
BUILD-INFO.txt
SHA256SUMS
```

artifact 名称包含目标 kernel release，保留 7 天。

> [!WARNING]
> CI 只能验证下载签名、源码补丁、目标 headers、编译器、Kbuild 与 vermagic，
> 无法验证云端不存在的真实 SN6140、NID 或 GPIO。下载 Actions 产物后仍须按
> 「第四步」在目标电脑上核对参数；CI 成功不是安装授权。

## 常见问题

### 为什么不完整编译内核？

当前配置中 Conexant codec 是独立模块 `m`。使用精确 headers 与
`Module.symvers` 可以只编译该模块，减少构建时间和安装范围。若驱动是内建
`y`，仍必须完整编译内核。

### 为什么每次升级内核都要重建？

`.ko` 与 kernel release、配置、导出符号和工具链绑定。即使源代码没有变化，
新的 `uname -r` 也需要新产物。

### 为什么模块未签名？

Arch 官方模块使用构建时生成的私钥，本仓库无法也不应该取得该私钥。未强制
签名的内核可以加载本地产物，但会记录 unsigned/out-of-tree taint。

### `Skipping BTF generation` 是错误吗？

如果没有 `pahole`，构建器会跳过可选的模块 BTF。BTF 用于调试和 tracing，
不是加载此模块所需的符号 ABI；vermagic 与 modpost 仍必须通过。

## License

除各文件另有 SPDX 标记外，本仓库按 GNU GPL version 2 或后续版本发布。
驱动补丁沿用被修改 Linux 源文件的 `GPL-2.0-or-later` 许可。详见
[COPYING](COPYING)。
