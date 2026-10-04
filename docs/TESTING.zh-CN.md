# 测试

[English](TESTING.md) · [首页](../README.zh-CN.md)

## 音频

重启后运行 `sn6140 status`，确认模块来自 `updates/dkms/`，且已加载版本匹配。
低音量播放，检查：

- 未插耳机时只有扬声器发声；插入耳机后扬声器静音，拔出后恢复。
- 连续插拔十次，切换仍正常。
- 播放时同时录制内置麦克风，两者互不打断。
- 休眠恢复后重复以上操作。

录音设备可从 `cat /proc/asound/pcm` 中的 DMIC 条目确认。
若出现爆音、两路同时发声或麦克风消失，停止测试并按[维护指南](ARCH.zh-CN.md)回滚。

安装前后可分别采集状态，便于比较：

```sh
./scripts/collect-sn6140.sh report.sn6140.before.txt
./scripts/collect-sn6140.sh report.sn6140.after.txt
journalctl -k -b | grep -Ei 'snd|sof|hda|SN6140|error|warn'
```

报告保存在本地 `reports/`，不纳入 Git。

## 开发检查

```sh
make check
make package
./tests/dkms-sandbox.sh
```

`make check` 检查语法和环境检测逻辑。sandbox 测试需要 bubblewrap、匹配的
headers、原始发行版模块及受支持的本机硬件；它在隔离目录中验证 DKMS
构建、旧模块冲突、pacman hook 安装和原模块恢复，不加载模块或更新启动镜像。

## 单独编译模块

`./scripts/build.sh` 为当前运行内核编译，产物位于 `dist/$(uname -r)/`，
其中 `BUILD-INFO.txt` 记录输入版本与 vermagic。缓存完整时可加 `--offline`。
安装使用 README 中的 DKMS 包流程。

CI 的目标参数位于 `.github/targets.env`，仅检查指定目标的编译结果。
