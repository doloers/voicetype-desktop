#!/bin/bash
# VoiceType：在本机启用 uinput 虚拟键盘（不用重启）
#
# 背景：当前运行的居然是旧内核 7.2.6-arch2-1，而磁盘上只有 7.2.7 的模块目录
#       （系统已更新内核、还没重启），所以 uinput 模块 modprobe 找不到、也从未加载，
#       /dev/uinput 那个节点是残留的空壳（打开也是 EACCES）。
# 做法：从 pacman 缓存里的旧内核包 linux-7.2.6.arch2-1 里取出 uinput.ko 直接 insmod
#       （版本与运行内核完全一致，vermagic 匹配），这样本次开机就能用，
#       不必为了语音输入专门重启；重启后由 /etc/modules-load.d/uinput.conf 自动加载。
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行"; exit 1; }

echo "=== 0/5 现状 ==="
uname -r
lsmod | grep -w uinput || echo "  uinput 未加载"

echo
echo "=== 1/5 从缓存内核包取出 uinput.ko ==="
PKG=/var/cache/pacman/pkg/linux-7.2.6.arch2-1-x86_64.pkg.tar.zst
if [ ! -f "$PKG" ]; then echo "❌ 缓存里没有 $PKG，需要重启到 7.2.7 后再加载"; exit 1; fi
rm -f /tmp/uinput.ko /tmp/uinput.ko.zst
tar --zstd -xOf "$PKG" usr/lib/modules/7.2.6-arch2-1/kernel/drivers/input/misc/uinput.ko.zst > /tmp/uinput.ko.zst
zstd -q -d -f /tmp/uinput.ko.zst -o /tmp/uinput.ko
ls -l /tmp/uinput.ko
modinfo /tmp/uinput.ko | grep -E "^(filename|vermagic|description|depends)" || true

echo
echo "=== 2/5 insmod（版本必须与运行内核一致） ==="
insmod /tmp/uinput.ko && echo "✅ insmod 成功" || { echo "❌ insmod 失败（可能需要重启到新内核）"; exit 1; }
lsmod | grep -w uinput
grep -i uinput /proc/misc || echo "⚠️ /proc/misc 里没看到 uinput"

echo
echo "=== 3/5 udev 规则改到 70-*（这样 TAG+=\"uaccess\" 才会被 73-seat-late 消费） ==="
OLD=/etc/udev/rules.d/99-voicetype-uinput.rules
NEW=/etc/udev/rules.d/70-voicetype-uinput.rules
if [ -f "$OLD" ]; then mv -f "$OLD" "$NEW"; echo "已把 99-… 改名成 70-…"; fi
cat > "$NEW" <<'EOF'
# VoiceType：允许当前登录图形会话的用户使用 /dev/uinput 注入虚拟键盘按键
# 注意：文件名要排在 73-seat-late.rules 之前，TAG+="uaccess" 才会被消费成 ACL
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput", TAG+="uaccess"
EOF
udevadm control --reload-rules
udevadm trigger --subsystem-match=misc --action=change --settle
sleep 1

echo
echo "=== 4/5 设备与权限 ==="
udevadm info -q all -n /dev/uinput 2>&1 | head -8
ls -l /dev/uinput
getfacl -p /dev/uinput 2>/dev/null | head -8

echo
echo "=== 5/5 以 haze 身份实测：能否创建虚拟键盘并注入 Ctrl+V ==="
runuser -u haze -- python3 - <<'PY'
import os, time
print("/dev/uinput 可写:", os.access("/dev/uinput", os.W_OK))
try:
    from evdev import UInput, ecodes as e
    ui = UInput({e.EV_KEY: [e.KEY_V, e.KEY_LEFTCTRL]}, name="voicetype-selftest")
    print("创建虚拟键盘 ✅", ui.device.path)
    time.sleep(0.3)
    for code, val in ((e.KEY_LEFTCTRL, 1), (e.KEY_V, 1), (e.KEY_V, 0), (e.KEY_LEFTCTRL, 0)):
        ui.write(e.EV_KEY, code, val); ui.syn()
    ui.close()
    print("注入 Ctrl+V ✅（剪贴板里若有内容，当前焦点窗口应被粘上）")
except Exception as ex:
    print("❌ 失败:", type(ex).__name__, ex)
PY

echo
echo "=== 回滚方法 ==="
echo "  rmmod uinput            # 本次开机内卸载（下次开机由 modules-load.d 再加载）"
echo "  rm -f /etc/udev/rules.d/70-voicetype-uinput.rules /etc/modules-load.d/uinput.conf"
echo "  udevadm control --reload-rules && udevadm trigger"
echo "  pacman -Rns python-evdev   # 如果彻底不用了"
echo "  rm -f /tmp/uinput.ko /tmp/uinput.ko.zst"
