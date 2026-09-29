#!/bin/sh
# mic-autofix.sh — 开机后检测麦克风采集，异常则自动修复
#
# 原理：
#   本机麦克风采集路径存在「suspend→resume 后失效」的偶发 bug（开机状态决定）。
#   脚本录制两段音频（中间隔 6 秒，让源挂起再唤醒）来复现该场景：
#     - 若某段是纯静音（全 0）→ 判定异常 → 禁用 suspend-on-idle 修复；
#     - 若两段都有信号（噪声底）→ 判定正常 → 保持省电（不修改任何配置）。
#
# 检测只在开机后跑一次；正常时零副作用、零额外功耗。

PA="$HOME/.config/pulse/default.pa"
LOG=/tmp/mic-autofix.log

log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG" 2>&1; }

# 录制约 1.5 秒，返回 ok / silent / nodata
detect() {
    timeout 2 parec --format=s16le --rate=16000 --channels=1 --raw 2>/dev/null \
        | python3 -c '
import sys
d = sys.stdin.buffer.read()
if not d:
    print("nodata")
else:
    nz = sum(1 for b in d if b)
    print("silent" if nz < len(d) // 100 else "ok")
'
}

# 0) 若上次开机应用过修复，先恢复默认（让检测在真实状态下进行）
if [ -f "$PA" ]; then
    rm -f "$PA"
    pulseaudio -k 2>/dev/null; sleep 2; pactl info >/dev/null 2>&1
    log "已移除上次修复，恢复 suspend-on-idle，重新检测"
fi

# 1) 等 PulseAudio 就绪
for i in 1 2 3 4 5 6 7 8 9 10; do
    pactl info >/dev/null 2>&1 && break
    sleep 2
done
sleep 2

# 2) 检测：录 → 等 6s（源挂起再唤醒）→ 再录
r1=$(detect)
log "第一次采样: $r1"
sleep 6
r2=$(detect)
log "第二次采样: $r2"

# 3) 判定
if [ "$r1" = "silent" ] || [ "$r2" = "silent" ]; then
    log "检测到麦克风静音 → 应用修复（禁用 suspend-on-idle）"
    mkdir -p "$(dirname "$PA")"
    printf '.include /etc/pulse/default.pa\nunload-module module-suspend-on-idle\n' > "$PA"
    pulseaudio -k 2>/dev/null; sleep 2; pactl info >/dev/null 2>&1
    log "修复完成：已禁用 suspend-on-idle"
elif [ "$r1" = "ok" ] && [ "$r2" = "ok" ]; then
    log "麦克风正常，保持省电（不修改配置）"
else
    log "采样无数据（$r1 / $r2），本次跳过（可能是启动早期）"
fi
exit 0
