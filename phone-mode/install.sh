#!/bin/sh
# VoiceType 手机模式安装脚本（postmarketOS / Phosh 等，用户级安装）
#
# 这是「桌面版」仓库里保留的上游手机模式：触发是长按音量键（evdev 被动读取），
# 注入用 /dev/uinput（需要 root 或 udev 授权 /dev/uinput）。
# 桌面用法请看仓库根目录的 README.md / install-desktop.sh。
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

echo "→ 安装主程序到 ~/.local/bin/voicetype"
install -Dm755 "$ROOT/voicetype" ~/.local/bin/voicetype

echo "→ 安装 systemd 用户服务（voicetype.service：音量键守护进程）"
mkdir -p ~/.config/systemd/user
cp "$DIR/voicetype.service" ~/.config/systemd/user/
systemctl --user daemon-reload

echo "→ 准备配置"
mkdir -p ~/.config/voicetype
if [ ! -f ~/.config/voicetype/config.json ]; then
    cp "$DIR/config.example.json" ~/.config/voicetype/config.json
    echo "  已生成 ~/.config/voicetype/config.json —— 请填入你的 api_key！"
else
    echo "  已存在 ~/.config/voicetype/config.json，跳过（不覆盖）"
fi

echo "→ 启用并启动服务"
systemctl --user enable --now voicetype.service

echo
echo "✅ 手机模式安装完成。"
echo "   自检：  voicetype --check"
echo "   日志：  journalctl --user -u voicetype.service -f"
