#!/bin/sh
# VoiceType 桌面版安装脚本（用户级，不需要 root）
#
# 桌面模式与手机版差别：
#   * 不读 evdev、不用 /dev/uinput（所以不需要 root / udev 规则）
#   * 由合成器快捷键调用 `voicetype --toggle` 开始/结束录音
#   * 注入用 wtype（zwp_virtual_keyboard），文本仍走剪贴板
#
# 前置：pacman -S wtype [opus-tools]
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "→ 安装主程序到 ~/.local/bin/voicetype"
install -Dm755 "$DIR/voicetype" ~/.local/bin/voicetype

echo "→ 安装通知图标到 ~/.local/share/voicetype/icons"
mkdir -p ~/.local/share/voicetype/icons
install -m644 "$DIR"/icons/*.svg "$DIR"/icons/png/*.png ~/.local/share/voicetype/icons/

echo "→ 安装 systemd 用户服务（voicetype-desktop.service）"
mkdir -p ~/.config/systemd/user
install -Dm644 "$DIR/systemd/voicetype-desktop.service" \
    ~/.config/systemd/user/voicetype-desktop.service
systemctl --user daemon-reload

echo "→ 准备配置"
mkdir -p ~/.config/voicetype
if [ ! -f ~/.config/voicetype/config.json ]; then
    install -m644 "$DIR/config.desktop.example.json" ~/.config/voicetype/config.json
    echo "  已生成 ~/.config/voicetype/config.json —— 请填入你的 api_key！"
else
    echo "  已存在 ~/.config/voicetype/config.json，跳过（不覆盖）"
fi

echo "→ 依赖检查"
for b in parec wl-copy notify-send wtype; do
    command -v "$b" >/dev/null || echo "  ⚠️  缺少 $b（parec 在 pipewire-pulse；wtype: pacman -S wtype）"
done
command -v opusenc >/dev/null || echo "  ⚠️  没装 opusenc（opus-tools），将直接上传 WAV，能用但慢一点"

echo "→ 启用并启动服务"
systemctl --user enable --now voicetype-desktop.service

echo
echo "✅ 安装完成。接着把快捷键加进 ~/.config/niri/config.kdl 的 binds 里："
echo '       Mod+V { spawn-sh "voicetype --toggle"; }   // 按一次开始，再按一次结束上屏'
echo "   然后：niri validate && niri msg action load-config-file"
echo
echo "   自检：voicetype --check"
echo "   日志：journalctl --user -u voicetype-desktop.service -f   （或 tail -f /tmp/voicetype.log）"
