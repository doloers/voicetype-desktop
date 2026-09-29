# VoiceType Desktop

> **按一下快捷键说话，松手（或停嘴）自动转文字并上屏** —— 为桌面 Linux / Wayland 打造的语音输入。

从 [VoiceType（手机版 pmos-voicetype）](https://github.com/doloers/pmos-voicetype) 移植而来：
把「长按音量键」换成**合成器快捷键**，把 `/dev/uinput` 之外的注入方式也补齐，
并按桌面场景重做了静音收尾、缓冲延迟等细节。在 **Arch Linux + niri 26.04 + PipeWire**、
ThinkPad X1 Carbon 上开发并日常使用。

```
按 Mod+V  ──►  parec 录音（16kHz/16bit/mono，流式）
                 ├─ 停嘴 ~1.2s 自动收尾（也可以再按一次 Mod+V）
                 ├─ PCM → OGG OPUS（opusenc，失败自动回退 WAV）
                 ├─ 豆包语音识别（volc.seedasr.auc 大模型 flash 接口）
                 └─ 结果写 wl-copy 剪贴板 → uinput 虚拟键盘发 Ctrl+V 上屏
                     （终端里自动改用 Ctrl+Shift+V）
```

## 特性

- ⌨️ **快捷键开关**：按一次开始录音，再按一次结束；停嘴静音自动收尾，连第二次都省
- 🧠 **场景自适应粘贴**：用 `niri msg` 查焦点窗口，终端自动 `Ctrl+Shift+V`，其它应用 `Ctrl+V`
- 🀄 **中文/emoji 天然安全**：文字走剪贴板（UTF-8），虚拟键盘只负责发组合键
- 🎚️ **静音自动收尾可校准**：`voicetype --levels 5` 打电平统计，`silence_rms` / `silence_ms` / `voice_chunks` 三个旋钮
- 🔁 **网络重试**：识别请求遇瞬时故障退避重试；失败/静音都有桌面通知
- 🩺 **自检**：`voicetype --check` 一次查依赖、设备、权限、会话环境、剪贴板、焦点检测、API
- 📝 **历史记录**：可选保存每次识别结果到 `~/.local/share/voicetype/history.log`
- 📱 **手机模式保留**：同一份程序不带参数启动仍是上游的音量键模式（见 `phone-mode/`）

## 依赖

| 类型 | 依赖 | 说明 |
|------|------|------|
| 命令 | `parec` | 录音（pipewire-pulse / PulseAudio） |
| 命令 | `wl-copy` / `wl-paste` | 剪贴板（wl-clipboard） |
| 命令 | `notify-send` | 通知提示（libnotify） |
| 命令 | `niri` | 查焦点窗口（用别的合成器可换 `focus_helper`） |
| Python | `python-evdev` | 创建 `/dev/uinput` 虚拟键盘 |
| 可选 | `opusenc`（opus-tools） | 上传前压缩，体积约为 WAV 的 1/10；没装则直传 WAV |

> 也支持 `injector: wtype`（`zwp_virtual_keyboard`，无需 root），但**在 niri 上实测注入不进终端**，
> 细节见 [NOTES.md](NOTES.md#1-wtype-在-niri-上注入不进终端所以默认改用-uinput)。

## 安装

```bash
git clone https://github.com/doloers/voicetype-desktop.git
cd voicetype-desktop

# 1) 用户级安装：程序 + systemd 用户服务 + 配置模板
bash install-desktop.sh

# 2) 一次性 root 配置：装 python-evdev、给 /dev/uinput 放行、开机自动加载 uinput
#    （只写 2 个文件，不动 sudoers，不需要把用户加入 input 组）
sudo bash setup-uinput-desktop.sh

# 3) 填 API Key（豆包语音控制台 → 录音文件识别大模型 → X-Api-Key）
$EDITOR ~/.config/voicetype/config.json      # "api_key": "……"

# 4) 加快捷键（~/.config/niri/config.kdl 的 binds 段）
#    Mod+V { spawn-sh "voicetype --toggle"; }
niri validate && niri msg action load-config-file
```

装完按 `Mod+V` 即可用。自检：`voicetype --check`；日志：`tail -f /tmp/voicetype.log`。

## 开机自启动

安装脚本已经把它接进**图形会话**（登录后自动起，不用手动开）：

```bash
systemctl --user is-enabled voicetype-desktop        # enabled
systemctl --user list-dependencies graphical-session.target | grep voicetype
# optional: 看看它到底什么时候起、有没有成功
systemctl --user status voicetype-desktop
journalctl --user -u voicetype-desktop -b
```

开机链路是这样串起来的，三个点都别漏：

| 环节 | 谁负责 | 怎么验证 |
|---|---|---|
| `uinput` 内核模块 | `/etc/modules-load.d/uinput.conf`（`setup-uinput-desktop.sh` 写） | `lsmod \| grep uinput`，`ls /dev/uinput` |
| `/dev/uinput` 权限 | `/etc/udev/rules.d/70-voicetype-uinput.rules`：`OWNER=<你>` + `TAG+="uaccess"` | `ls -l /dev/uinput` 应显示属主是你 |
| 服务随会话启动 | `systemctl --user enable voicetype-desktop`（`WantedBy=graphical-session.target`） | 上面两条命令 |

两个容易踩的点，脚本都已经处理：

- **权限不能只靠会话 ACL**：内核模块在 sysinit 阶段就加载、设备节点随即创建，那时用户会话还没激活，
  `uaccess` ACL 还没落下来。所以规则里写了 `OWNER=<你>`，服务启动时直接就有写权限。
  （另外规则必须叫 `70-*`：`TAG+="uaccess"` 要早于 `73-seat-late.rules` 才会被消费成 ACL。）
- **启动时 `/dev/uinput` 可能还没就绪**：守护进程对注入器初始化做了重试（默认 10 次 × 3 秒），
  失败也不会把自己弄死；systemd 侧还有 `Restart=on-failure`。

关掉自启动：`systemctl --user disable --now voicetype-desktop`。

## 用法

```bash
voicetype                 # 手机模式守护进程（音量键）
voicetype --serve         # 桌面模式守护进程（socket，一般由 systemd 拉起）
voicetype --toggle        # 开始 / 停止录音（绑定到快捷键）
voicetype --start/--stop  # 只开始 / 只停止
voicetype --status        # 看当前状态
voicetype --enter         # 注入一次回车（想的话可以再绑一个键）
voicetype --check         # 自检
voicetype --levels N      # 录 N 秒打电平统计（校准静音阈值）
voicetype --record N      # 录 N 秒 → 识别 → 上屏（调试）
```

服务管理：

```bash
systemctl --user status voicetype-desktop
systemctl --user restart voicetype-desktop
journalctl --user -u voicetype-desktop -f      # 或 tail -f /tmp/voicetype.log
```

## 配置 `~/.config/voicetype/config.json`

见 [`config.desktop.example.json`](config.desktop.example.json)，桌面相关键：

| 键 | 默认 | 说明 |
|---|---|---|
| `api_key` | — | **必填**，豆包语音控制台的 API Key |
| `injector` | `uinput` | `uinput`（推荐） / `wtype` |
| `focus_helper` | `niri` | 用 `niri msg --json focused-window` 查焦点应用 |
| `auto_stop` / `silence_ms` / `silence_rms` / `voice_chunks` | `true` / `1200` / `300` / `3` | 静音自动收尾；`voice_chunks` = 连续多少个 100ms 超阈值才算「真在说话」（防按键/通知声误触） |
| `latency_ms` | `20` | `parec --latency-msec`；**别设 0**（默认会丢开头 ~2 秒） |
| `max_seconds` / `min_seconds` | `120` / `0.4` | 单次录音上限 / 太短忽略 |
| `paste_mods` / `paste_mods_terminal` / `paste_key` | `Ctrl` / `Ctrl+Shift` / `V` | 上屏组合键 |
| `terminal_apps` | `foot, alacritty, kitty, …` | 判定为终端的 app_id 列表 |
| `opus_bitrate` | `24` | OPUS 码率（kbps），`0` = 直接传 WAV |
| `notify` / `save_history` | `true` | 桌面通知 / 保存识别历史 |
| `icons` | 指向自带的平面图标：`~/.local/share/voicetype/icons/{mic,busy,ok,warn,error}.png` | 通知图标：值是**文件路径**（支持 `~`），也可以是 Freedesktop 图标名（由系统图标主题解析） |
| `mode` | `desktop` | 只影响 `--check` 的提示（桌面上不要求音量键设备存在） |
| `injector_retries` | `10` | 启动时注入器初始化重试次数（每次间隔 3s，防开机时 `/dev/uinput` 未就绪） |

改完配置**不用重启服务**（每次开录前会重读）。

### 通知图标（自带平面图标）

仓库 `icons/` 是一套平面化（单色线条）图标，`install-desktop.sh` 会装到 `~/.local/share/voicetype/icons/`，
配置里默认就指向它们：

| 状态 | 文件 | 颜色 |
|---|---|---|
| 录音中 / 麦克风 | `mic.png` | 浅灰 `#e6e6e6` |
| 识别中 | `busy.png` | 浅灰 `#e6e6e6` |
| 已上屏 | `ok.png` | 绿 `#7bd88f` |
| 录音太短 / 没录到声音 | `warn.png` | 琥珀 `#ffcc66` |
| 识别失败 | `error.png` | 红 `#ff6b6b` |

想换颜色或换成纯灰阶：编辑 `icons/*.svg` 里 `fill` 的值（源文件里只有一两种颜色，很好改），
然后重新生成并安装：

```bash
./icons/build.sh                                   # svg -> icons/png/*.png（默认 48px，SIZE=64 ./icons/build.sh 可调）
install -m644 icons/png/*.png ~/.local/share/voicetype/icons/
```

> **为什么用 PNG 而不是直接让 dunst 读 SVG**：通知守护进程走 gdk-pixbuf，而 gdk-pixbuf 的 SVG loader
> 不一定装了（本机 Arch 上 dunst 1.13 就没有），此时 SVG 图标会**静默不显示**。PNG 到处都能加载。

## 排障

| 现象 | 处理 |
|---|---|
| 按快捷键没反应 | `systemctl --user status voicetype-desktop`；`tail -20 /tmp/voicetype.log` |
| 通知「没听到说话」 | 麦没声音：`pactl list short sources`、`voicetype --levels 5` 看电平 |
| 通知「未配置 api_key」 | 填 `~/.config/voicetype/config.json` |
| 识别成功但没上屏 | `voicetype --check` 看 `/dev/uinput` 是否可写（跑 `setup-uinput-desktop.sh`） |
| 重启后按键没反应 | `systemctl --user status voicetype-desktop`；`ls -l /dev/uinput` 属主是否是你；`lsmod \| grep uinput` |
| 提前自动收尾（还没说就停） | 环境噪声大：把 `silence_rms` 调高 或 `voice_chunks` 调大 |
| 通知没图标 / 图标空白 | ① 用图标**名**时主题里可能没有：给 dunst 的 `icon_path` 加上实际目录（如 `/usr/share/icons/AdwaitaLegacy/48x48/legacy/`），或在 `icons` 里直接写文件路径；② 给的是 **SVG** 路径时：dunst 用的 gdk-pixbuf 可能没有 SVG loader，换 PNG（`voicetype --check` 会检查文件是否存在） |
| API 报 `45000010` / `45000030` | Key 无效 / 能力未开通（豆包控制台「开通管理」） |

更多实测细节（为什么不用 wtype、`ID_INPUT_KEYBOARD` 标签、`uaccess` 规则顺序、`parec` 缓冲）
见 **[NOTES.md](NOTES.md)**。

## 目录结构

```
voicetype                       主程序（桌面模式 + 手机模式，单文件 Python）
install-desktop.sh              桌面安装（用户级）
setup-uinput-desktop.sh         /dev/uinput 一次性 root 配置
config.desktop.example.json     桌面配置模板
icons/                          通知图标（平面化 SVG 源 + 生成的 PNG，见 icons/build.sh）
systemd/voicetype-desktop.service
NOTES.md                        实测笔记与踩坑记录
phone-mode/                     上游手机模式（音量键）：install.sh / config / systemd / extras
```

## 与上游的关系

上游 [pmos-voicetype](https://github.com/doloers/pmos-voicetype) 是给 Linux 手机
（postmarketOS / Phosh）写的。本项目把触发从 evdev 音量键改成合成器快捷键、
注入改为可插拔（`uinput` / `wtype`）、录音改流式并加静音收尾，其余（识别、剪贴板、重试、通知、
自愈开关）沿用。手机模式代码路径保持兼容，`voicetype` 不带参数即还原上游行为。

## 许可

[MIT](LICENSE) © 2026 doloers
