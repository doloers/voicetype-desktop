# VoiceType Desktop —— 实测笔记与踩坑记录

环境：Arch Linux + niri 26.04 + PipeWire，ThinkPad X1 Carbon Gen 14。

上游项目 [`doloers/pmos-voicetype`](https://github.com/doloers/pmos-voicetype) 是为
**Linux 手机（postmarketOS / Phosh / OnePlus 6）** 写的：长按音量键录音、松手识别、自动上屏。

本项目把它搬到**桌面**上，用**合成器快捷键**取代音量键。改动尽量小、手机模式仍兼容。

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
| `/dev/uinput` 虚拟键盘 | **`uinput`（默认）**，`wtype` 作备用 | wtype 更干净、不要 root，但实测在 niri 26.04 上**注入不进终端**（见坑 1）；uinput 是内核级设备，合成器当真实键盘，稳 |
| `wt-focus` 查焦点 | **`niri msg --json focused-window`** | 本机就带，少装一个工具 |
| 录音写文件后再读 | **流式录音 + RMS 静音检测** | 支持「说完静音 1.2s 自动收尾」，第二次按键都可省 |
| `parec` 默认缓冲 | **加 `--latency-msec=20`** | 实测：不加时 parec 攒 ~2s 才吐数据，**开头 2 秒直接丢** |
| 全 0 就重启 PulseAudio | 默认关闭（`heal_mic:false`），只弹提示 | PipeWire 上没有手机上那个挂起失效的毛病 |
| 服务 `voicetype.service` | `voicetype-desktop.service`（`--serve`） | 两者的 `ExecStart` 不同，互不干扰 |
| 上游目录 `extras/`、手机安装脚本 | 归到 `phone-mode/` | 和桌面用法分开，避免混淆 |

## 三、用法

```bash
# 1) 安装（用户级，不需要 root）
bash install-desktop.sh
sudo bash setup-uinput-desktop.sh

# 2) uinput 注入需要的一次性 root 配置（装 python-evdev + 给 /dev/uinput 放行 + 开机加载 uinput）
sudo bash setup-uinput-desktop.sh

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
| `mode` | `desktop` | 只影响自检提示：`desktop` 不要求音量键设备在 |
| `injector` | `uinput` | `uinput`（推荐，需跑一次 `setup-uinput-desktop.sh`） / `wtype` |
| `focus_helper` | `niri` | 用 `niri msg` 查焦点窗口 app_id |
| `auto_stop` / `silence_ms` / `silence_rms` / `voice_chunks` | `true` / `1200` / `300` / `3` | 说完静音自动收尾；RMS 阈值太小会误判环境噪声，太大说话不停；`voice_chunks` = 连续多少个 100ms 超阈值才算「真在说话」（防按键/通知声误触） |
| `latency_ms` | `20` | `parec --latency-msec`；**别设 0**（默认会丢开头 ~2 秒） |
| `max_seconds` | `120` | 单次录音上限 |
| `wtype_delay_ms` | `30` | 修饰键按住时长，个别应用收到组合键太快会漏 |
| `heal_mic` | `false` | 桌面关掉 PulseAudio 自愈 |

## 五、已知限制 / 坑（都是实测记录）

### 1. `wtype` 在 niri 上注入不进终端（所以默认改用 uinput）

- niri 26.04 **确实** advertise 了 `zwp_virtual_keyboard_manager_v1`（wtype 能绑定、能把
  keymap/按键请求发出去，无协议错误），`fuzzel` 这类自带 keymap 的客户端**收得到**，
  但 `foot` / `alacritty` 这类会采用合成器下发 keymap 的终端**一个键都收不到**
  （`stty` raw + `cat` 落盘验证 0 字节；重复注入也一样）。
- 对比实验：同样的注入换成 uinput 就能打进 foot（截图里能看到粘贴结果），也能触发 niri 自己的
  `Mod+R` 配置重载 —— 所以问题在 wtype↔合成器那条链，不在我们的注入逻辑。
- 结论：桌面默认 `injector: uinput`。wtype 的代码保留着（wlroots 系大概能用，也方便回合上游）。

### 2. uinput 设备必须声明「整套标准键盘键位」

- libinput 只认带 udev `ID_INPUT_KEYBOARD=1` 标签的设备。python-evdev 只声明
  `V/CTRL/SHIFT/ENTER/音量键`（甚至 `A..Z`、`ESC+ENTER`）建出来的 uinput 设备，
  udev 只给 `ID_INPUT=1` + `ID_INPUT_KEY=1`，**按键会被 libinput 静默丢弃**。
- 实测：声明一整套标准键位（ESC 数字字母功能区修饰键…见代码里的 `_KEYBOARD_KEYS`）
  才会拿到 `ID_INPUT_KEYBOARD=1`。验证：设备活着时
  `udevadm info -q all -n /dev/input/eventN | grep ID_INPUT`。

### 3. `/dev/uinput` 权限与内核模块

- 需要 root 跑一次 `setup-uinput-desktop.sh`：装 `python-evdev`、写
  `/etc/udev/rules.d/70-voicetype-uinput.rules`（`MODE=0660 GROUP=input TAG+="uaccess"`，
  给当前登录会话加 ACL，不必把用户加进 `input` 组）、写 `modules-load.d/uinput.conf`。
  - 规则文件名必须是 `70-*`：`TAG+="uaccess"` 要早于 `73-seat-late.rules` 才会被消费成 ACL。
- 本机特殊情况：运行内核是 7.2.6 而磁盘上只有 7.2.7 的模块（已更新未重启），
  `modprobe uinput` 找不到模块；脚本会从 pacman 缓存里的旧内核包取出 `uinput.ko` 直接
  `insmod`（版本一致所以能加载），不用为语音输入专门重启；重启后靠 `modules-load.d` 自动加载。

### 4. `parec` 不加 `--latency-msec` 会吃掉开头约 2 秒音频

实测：4s 请求只回 2s，首包 2.02s 才到；加 `--latency-msec=20` 后首包 0.08s、丢 0.02s。
手机上长按 400ms 才开始说，那 2 秒正好是按键空档所以一直没人发现；
桌面「按下就说话」不修就是直接丢句首。已在 `recorder_cmd()` 里默认加上（`latency_ms`）。

### 5. niri 不支持按键释放绑定

`niri validate` 实测：一个键位只能一个 action，没有 release 语法 → 做不了「按住说话」。
想要 push-to-talk 只有两条路：① 用 evdev 抓键（要 `input` 组 / udev 规则，能读到按下与松开）；
② 用 `keyd` 之类底层改键工具。目前是「按一下开始 / 再按一下结束」，外加静音自动收尾。

### 6. 其它

- 剪贴板会被识别结果覆盖（原本内容不保存）。
- 豆包接口要联网；`X-Api-Key` 无效返回 `45000010`，能力未开通是 `45000030`。
- 第一次录音时 PipeWire 唤醒麦克风可能丢开头约 100ms，`min_seconds` 别设太小。

## 六、与上游的关系

改动集中在 `voicetype` 一个文件里（用 `injector` 抽象注入方式、`Recorder` 抽象录音、
新增 `--serve/--toggle/--start/--stop/--status/--enter` 和 `Server`/`ctl`），
另加 `systemd/voicetype-desktop.service`、`install-desktop.sh`、`setup-uinput-desktop.sh`、
`config.desktop.example.json`、本文件。上游手机模式（无参数 = evdev 守护进程）行为保持不变，
手机相关文件归在 `phone-mode/`。
