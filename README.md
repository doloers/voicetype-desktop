# VoiceType

> 长按音量键说话，松手自动转文字并上屏 —— 为 Linux 手机（postmarketOS / Phosh）打造。

在 OnePlus 6（Qualcomm SDM845）+ postmarketOS + Phosh 上开发并日常使用：**长按音量下键说话，松手后自动把识别结果粘贴到当前焦点窗口**。

## 特性

- 🎤 **长按音量下键** → 录音；松开 → 语音识别 → 自动上屏
- ⏎ **长按音量上键** → 注入一次回车（Enter）
- 🔊 **短按音量键** → 忽略（音量照常调节；采用被动读取，不抢占设备）
- 🖥️ **智能粘贴**：终端自动用 `Ctrl+Shift+V`，其它应用用 `Ctrl+V`
- 🔁 **网络重试**：识别请求遇到瞬时网络/域名解析故障自动退避重试
- 🩺 **麦克风自愈**：录音为纯静音（采集路径失效）时自动重启 PulseAudio 修复并提示重说
- 🗜️ **OPUS 压缩**：上传前把 PCM 压成 OGG OPUS（约为 WAV 的 1/8），识别更快、更省流量
- 📝 **历史记录**：可选保存每次识别结果

## 工作原理

```
长按音量下键
   └─ parec 录音（16kHz / 16bit / mono）
         └─ 松开
              ├─ PCM → OGG OPUS（opusenc，失败自动回退 WAV）
              ├─ 调用豆包语音识别（volc.seedasr.auc 大模型 flash 接口）
              └─ 结果写入剪贴板 → 用 /dev/uinput 虚拟键盘发送 Ctrl+V
```

> **为什么用 uinput + 剪贴板，而不是 `wtype`？**
> 剪贴板天然是 UTF-8，中文/emoji 不会出问题；`uinput` 虚拟键盘只负责发 `Ctrl+V` 这类按键组合。

## 依赖

| 类型 | 依赖 | 说明 |
|------|------|------|
| Python | `evdev` | 读取音量键、创建虚拟键盘 |
| 命令 | `parec` | 录音（PulseAudio / PipeWire） |
| 命令 | `wl-copy` / `wl-paste` | 剪贴板（wl-clipboard） |
| 命令 | `notify-send` | 通知提示 |
| 可选 | `opusenc`（opus-tools） | 音频压缩；**没有则自动回退 WAV** |
| 可选 | `wt-focus` | 检测焦点应用以决定粘贴组合键 |

另外需要系统允许写入 `/dev/uinput`（通常通过 sudoers 或 udev 规则授权）。

## 安装

```bash
# 1. 主程序
install -Dm755 voicetype ~/.local/bin/voicetype

# 2. 配置
mkdir -p ~/.config/voicetype
cp config.example.json ~/.config/voicetype/config.json
$EDITOR ~/.config/voicetype/config.json        # 填入 api_key 等

# 3. systemd 用户服务
mkdir -p ~/.config/systemd/user
cp systemd/voicetype.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now voicetype.service

# 4. 查看日志
journalctl --user -u voicetype.service -f
# 或
tail -f /tmp/voicetype.log
```

## 配置

配置文件：`~/.config/voicetype/config.json`（见 `config.example.json`）

| 键 | 默认 | 说明 |
|----|------|------|
| `api_key` | — | 豆包语音 API Key（**必需**） |
| `resource_id` | `volc.seedasr.auc` | 豆包资源 ID（录音文件识别大模型 2.0） |
| `endpoint` | `…/recognize/flash` | 识别接口地址 |
| `trigger_device` | `Volume keys` | 触发的 evdev 设备名 |
| `trigger_key` | `KEY_VOLUMEDOWN` | 长按此键录音 |
| `enter_key` | `KEY_VOLUMEUP` | 长按此键注入回车 |
| `hold_ms` | `400` | 长按判定阈值（ms） |
| `enter_hold_ms` | `400` | 回车触发的长按阈值（ms） |
| `max_seconds` | `120` | 单次录音上限（秒） |
| `min_seconds` | `0.4` | 太短则忽略（秒） |
| `paste_mods` | `["LEFTCTRL"]` | 普通应用粘贴组合键 |
| `paste_mods_terminal` | `["LEFTCTRL","LEFTSHIFT"]` | 终端粘贴组合键 |
| `terminal_apps` | `[...]` | 判定为终端的 app_id 列表 |
| `opus_bitrate` | `24` | OPUS 码率（kbps）；**`0` 则直接传 WAV** |
| `suspend_reload_idle` | `900` | 自愈后空闲多少秒恢复 `suspend-on-idle`（省电）；`0` 不恢复 |
| `grab` | `false` | 是否独占音量键（`false` 时不影响系统音量调节） |
| `notify` | `true` | 是否弹通知 |
| `save_history` | `true` | 是否保存识别历史 |

## 参数

```bash
voicetype               # 启动守护进程（正常用法）
voicetype --record N    # 手动录 N 秒并粘贴（调试）
voicetype --devices     # 列出输入设备
voicetype --check       # 自检
voicetype --config      # 打印当前配置
```

## 平台特定说明

本机为 OnePlus 6 / SDM845 的 postmarketOS，部分逻辑与平台相关，见 `extras/`：

- **`extras/call_audio_idle_suspend_workaround`**
  postmarketOS 自带的通话 workaround 会在通话结束后**无条件重装** `module-suspend-on-idle`，
  会让通话后的首次录音失效。本地版改为「记录通话前状态，仅在原本加载时才恢复」，避免无谓失效。
  用法：覆盖发行版服务（systemd drop-in）。

- **`extras/mic-autofix.sh`**（**已停用，仅留档**）
  早期的「开机检测麦克风、静音则禁用 suspend-on-idle」方案。因为麦克风可能在开机**之后**才失效，
  该方案存在盲区，已被主程序内的**自愈**逻辑取代。

### 关于麦克风「挂起→唤醒失效」

本机 WCD934x 的采集路径在 `module-suspend-on-idle` 把麦克风挂起后再唤醒时**偶发失效**（录出纯数字静音）。
主程序的处理方式：录音结束若发现 PCM 全为 0，则自动
`重启 PulseAudio + 卸载 module-suspend-on-idle` 并弹窗提示重说；之后空闲一段时间再自动把
`suspend-on-idle` 装回去以省电（见 `suspend_reload_idle`）。这样在**可靠**与**省电**之间取平衡。

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 许可

MIT
