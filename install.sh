#!/bin/sh
# VoiceType 安装脚本（用户级安装）
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "→ 安装主程序到 ~/.local/bin/voicetype"
install -Dm755 "$DIR/voicetype" ~/.local/bin/voicetype

echo "→ 安装 systemd 用户服务"
mkdir -p ~/.config/systemd/user
cp "$DIR/systemd/voicetype.service" ~/.config/systemd/user/
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
echo "✅ 安装完成。"
echo "   自检：  voicetype --check"
echo "   日志：  journalctl --user -u voicetype.service -f"
