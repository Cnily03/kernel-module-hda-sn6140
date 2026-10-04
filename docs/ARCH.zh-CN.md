# 维护

[English](ARCH.md) · [首页](../README.zh-CN.md)

## 更新失败时

先检查 `sn6140 status` 和 DKMS 输出中提示的 `make.log`。
pacman 的构建 hook 失败不会撤销内核升级，确认修复成功后再重启。

| 错误 | 处理 |
| --- | --- |
| `Manual override exists` | 移除目标内核的旧手工模块 |
| headers 缺失或版本不符 | 安装与 `linux-zen` 同版本的 `linux-zen-headers` |
| 下载、验签失败 | 检查网络、系统时间和缓存；保留失败文件，不跳过验签 |
| `Compiler mismatch` | 核对 GCC 与目标内核的构建版本 |
| 补丁或编译失败 | 保留日志，等待补丁适配，暂用备用内核 |
| `Key was rejected` | 检查 DKMS 签名证书是否受内核信任 |
| 已安装但未加载 | 核对启动内核及 initramfs/UKI 是否更新 |

排除原因后重试：

```sh
target=$(pacman -Qlq linux-zen | sed -n 's|^/usr/lib/modules/\([^/]*\)/pkgbase$|\1|p')
version=$(pacman -Q sn6140-linux-zen-dkms | awk '{print $2}')
sudo dkms install -m sn6140 -v "${version%-*}" -k "$target"
```

手工重试后，mkinitcpio 用户运行 `sudo mkinitcpio -P` 更新镜像；
dracut/自定义 UKI 使用对应生成流程。正常 pacman 更新由系统 hooks 处理。

## 恢复原驱动

卸载用 `sudo pacman -R sn6140-linux-zen-dkms`，重启后生效。
DKMS 会恢复保存在 `/var/lib/dkms/sn6140/` 下的原模块，勿直接删除该目录。
下载缓存 `/var/cache/sn6140/` 会保留。

若目标内核无法启动，从备用内核或安装介质进入系统后卸载该包并更新启动镜像。
原模块备份丢失时，重新安装对应的 `linux-zen` 包。
