# 更新日志

本项目从 [VoiceType（手机版）](https://github.com/doloers/pmos-voicetype) 移植而来，独立发版。
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

---

## [0.1.0] — 2026-09-29

首个版本：桌面 Linux / Wayland 上的快捷键语音输入。

### ✨ 功能

- **快捷键开关**：`voicetype --toggle` 按一次开始、再按一次结束（配套 niri 绑定 `Mod+V`）；
  守护进程用 Unix socket（`$XDG_RUNTIME_DIR/voicetype.sock`）收命令，
  另有 `--start/--stop/--status/--enter`；服务没在跑时会自动 `systemctl --user start`
- **静音自动收尾**：流式录音 + RMS 电平判定，说完静音 1.2s 自动结束；
  `voice_chunks` 要求连续多个窗口超阈值才「武装」收尾，避免按键/通知声误触
- **电平校准工具**：`voicetype --levels N` 打印环境电平统计，用来调 `silence_rms`
- **可插拔注入**：`injector: uinput`（内核虚拟键盘，推荐）/ `wtype`（zwp_virtual_keyboard）
- **焦点自适应粘贴**：`focus_helper: niri` 直接用 `niri msg --json focused-window`，
  终端自动 `Ctrl+Shift+V`、其它应用 `Ctrl+V`（不再需要额外的 `wt-focus` 小工具）
- 桌面模式下 `heal_mic` 默认关闭（重启 PulseAudio 是手机 WCD934x 的特有毛病）
- `mode: desktop|phone`：桌面上自检不再要求音量键设备存在

### 🐛 修复（都是实测出来的）

- **`parec` 不加 `--latency-msec` 会吃掉开头约 2 秒音频**：4s 请求只回 2s、首包 2.02s 才到；
  加 `--latency-msec=20` 后首包 0.08s、丢 0.02s。手机上是长按空档所以一直没暴露
- **uinput 设备必须声明整套标准键盘键位**：只声明少数几个键（哪怕 `A..Z`、`ESC+ENTER`）时，
  udev 只给 `ID_INPUT=1` 而拿不到 `ID_INPUT_KEYBOARD=1`，libinput 会把按键**静默丢弃**
- **`wtype -s` 收整数毫秒**（`atoi` 解析），传 `0.03` 会被当 0 报错

### 📄 文档

- `NOTES.md`：移植前后的对照、为什么放弃 wtype、`uaccess` 规则顺序、
  niri 没有「松键绑定」所以做不了按住说话等实测记录

### ⚠️ 已知限制

- `wtype` 注入在 niri 26.04 上进不了终端（`foot`/`alacritty` 收不到，`fuzzel` 能收到），
  所以桌面默认 `uinput`
- 剪贴板会被识别结果覆盖
- 依赖云识别接口（豆包 `volc.seedasr.auc`），需要 `api_key` 且要联网
