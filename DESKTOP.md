# VoiceType 桌面版（Arch + niri + PipeWire）

上游项目 [`doloers/pmos-voicetype`](https://github.com/doloers/pmos-voicetype) 是为
**Linux 手机（postmarketOS / Phosh / OnePlus 6）** 写的：长按音量键录音、松手识别、自动上屏。

这份分支把它搬到**笔记本桌面**上，用**合成器快捷键**取代音量键。改动尽量小、可直接回合上游。

## 一、原版是怎么工作的（研究结论）

```
音量键 (evdev, 被动读取)  →  长按 ≥400ms 开始 parec 录音
                           松开 → PCM →(opusenc)→ OGG OPUS
                                → 豆包语音 flash 识别接口 (volc.seedasr.auc)
                                → 结果写 wl-copy 剪贴板
                                → /dev/uinput 虚拟键盘发 Ctrl+V（终端用 Ctrl+Shift+V）
```

关键设计点：

| 点 | 说明 |
|---|---|
| 触发 | `evdev` **被动读取**音量键（不 grab），短按透传系统调音量，长按才录音 |
| 注入 | 文本走**剪贴板**（UTF-8 天然安全），虚拟键盘只负责发 `Ctrl+V` 组合键 |
| 焦点判断 | 外部小工具 `wt-focus` 拿焦点窗口 app_id，终端 → `Ctrl+Shift+V` |
| 识别 | 豆包大模型 flash 接口，`resource_id=volc.seedasr.auc`，约 0.8 元/小时，需 `api_key` |
| 稳定性 | 网络失败退避重试 5 次；录音全 0（采集路径挂起失效）→ 重启 PulseAudio 自愈（**手机 WCD934x 特有**） |

## 二、搬到桌面要改什么

| 手机 | 桌面（本机） | 原因 |
|---|---|---|
| 音量键长按（evdev） | **niri 快捷键 → socket 命令** | 笔记本音量键要留给调音量；且 niri 无「松键」绑定，故用**按一下开始 / 再按一下结束** |
| `/dev/uinput` 虚拟键盘 | **`wtype`**（zwp_virtual_keyboard） | 无需 root、无需 udev 规则；niri 已实现该协议 |
| `wt-focus` 查焦点 | **`niri msg --json focused-window`** | 本机就带，少装一个工具 |
| 录音写文件后再读 | **流式录音 + RMS 静音检测** | 支持「说完静音 1.2s 自动收尾」，第二次按键都可省 |
| `parec` 默认缓冲 | **加 `--latency-msec=20`** | 实测：不加时 parec 攒 ~2s 才吐数据，**开头 2 秒直接丢** |
| 全 0 就重启 PulseAudio | 默认关闭（`heal_mic:false`），只弹提示 | PipeWire 上没有手机上那个挂起失效的毛病 |
| 服务 `voicetype.service` | `voicetype-desktop.service`（`--serve`） | 两者的 `ExecStart` 不同，互不干扰 |

## 三、用法

```bash
# 安装（用户级，不需要 root）
bash install-desktop.sh

# niri 快捷键（config.kdl 的 binds 里）
Mod+V { spawn-sh "voicetype --toggle"; }

# 手动测试
voicetype --serve        # 前台跑守护进程（正常走 systemd）
voicetype --toggle       # 等同按快捷键
voicetype --check        # 自检（依赖/设备/剪贴板/焦点/API 全查一遍）
voicetype --levels 5     # 录 5 秒只打电平统计，用来校准 silence_rms

systemctl --user status voicetype-desktop
tail -f /tmp/voicetype.log          # 详细日志
```

**交互**：按一次 `Mod+V`（叮一声通知「录音中…」）→ 说话 → 再按一次结束（或停嘴 1.2s 自动结束）
→ 通知「识别中…」→ 识别完自动把文字粘到当前焦点窗口，通知「已上屏」。

## 四、配置文件 `~/.config/voicetype/config.json`

桌面相关的键（其余继承上游默认值）：

| 键 | 桌面默认 | 说明 |
|---|---|---|
| `api_key` | — | **必填**，豆包语音控制台拿 |
| `injector` | `wtype` | `wtype`（桌面） / `uinput`（手机） |
| `focus_helper` | `niri` | 用 `niri msg` 查焦点窗口 app_id |
| `auto_stop` / `silence_ms` / `silence_rms` / `voice_chunks` | `true` / `1200` / `300` / `3` | 说完静音自动收尾；RMS 阈值太小会误判环境噪声，太大说话不停；`voice_chunks` = 连续多少个 100ms 超阈值才算「真在说话」（防按键/通知声误触） |
| `latency_ms` | `20` | `parec --latency-msec`；**别设 0**（默认会丢开头 ~2 秒） |
| `max_seconds` | `120` | 单次录音上限 |
| `wtype_delay_ms` | `30` | 修饰键按住时长，个别应用收到组合键太快会漏 |
| `heal_mic` | `false` | 桌面关掉 PulseAudio 自愈 |

## 五、已知限制 / 坑

- **`parec` 不加 `--latency-msec` 会吃掉开头约 2 秒音频**（实测：4s 请求只回 2s，
  首包 2.02s 才到；加 `--latency-msec=20` 后首包 0.08s、丢 0.02s）。
  手机上是长按 400ms 才开始说，所以丢的那 2 秒正好是按键的空档，一直没人发现；
  桌面是「按下就说话」，不修就是丢句首。已在 `recorder_cmd()` 里默认加上（`latency_ms`）。
- **niri 不支持按键释放绑定**（`niri validate` 实测：一个键位只能一个 action，没有 release 语法），
  所以做不了「按住说话」。真想要 push-to-talk 只有两条路：
  ① 用 evdev 抓键（要 `input` 组 / udev 规则，能读到按键的按下与松开）；
  ② 用 `keyd` 之类的底层改键工具。
- 剪贴板会被覆盖（识别结果写进剪贴板），如果想保留原剪贴板内容可以后续加「粘贴后恢复」。
- 豆包接口要联网；`X-Api-Key` 无效会返回 `45000010`，能力未开通是 `45000030`。
- 第一次录音时 PipeWire 要唤醒麦克风，开头约 100ms 可能丢，`min_seconds` 别设太小。

## 六、与上游的关系

改动集中在 `voicetype` 一个文件里（用 `injector` 抽象注入方式、`Recorder` 抽象录音、
新增 `--serve/--toggle/--start/--stop/--status/--enter` 和 `Server`/`ctl`），
另加 `systemd/voicetype-desktop.service`、`install-desktop.sh`、`config.desktop.example.json`、
本文件。上游手机模式（无参数 = evdev 守护进程）行为保持不变，可直接提 PR。
