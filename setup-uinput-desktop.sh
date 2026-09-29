#!/bin/bash
# VoiceType Desktop：启用 uinput 虚拟键盘所需的一次性 root 配置
#
# 做三件事（幂等、可回滚、不碰 sudoers、不加 input 组）：
#   1. 装 python-evdev（创建 /dev/uinput 虚拟键盘用）
#   2. 保证 uinput 内核模块开机自动加载（/etc/modules-load.d/uinput.conf）
#   3. 写 udev 规则，把 /dev/uinput 归给当前用户（OWNER）+ uaccess ACL 双保险
#
# 为什么用 OWNER：开机时内核模块在 sysinit 阶段就加载、设备节点随即创建，
# 而那时用户的图形会话还没激活，uaccess ACL 还没落下来 —— 只要 OWNER 是你自己，
# 服务随会话启动时就能直接写 /dev/uinput，不看时序脸色。
# 规则文件名必须是 70-*：TAG+="uaccess" 要早于 73-seat-late.rules 才会被消费成 ACL。
#
# 特例：运行内核与磁盘上的模块目录不一致（刚更新内核、还没重启）时 modprobe 找不到
# uinput，脚本会从 pacman 缓存里的对应内核包中取出 uinput.ko 直接 insmod，
# 这样不用为语音输入专门重启；重启后由 modules-load.d 自动加载。
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行: sudo bash $0"; exit 1; }

TARGET_USER="${SUDO_USER:-$(getent passwd 1000 | cut -d: -f1)}"
[ -n "$TARGET_USER" ] || { echo "❌ 判断不出目标用户，请手动改脚本里的 TARGET_USER"; exit 1; }

# ⚠️ 不要用 `lsmod | grep -q uinput` 判断：脚本开了 pipefail，grep -q 命中就早退，
#    lsmod 收到 SIGPIPE 变成 141，整条管道就被判成失败（假阴性）。
mod_loaded() { lsmod | grep -w uinput >/dev/null; }
echo "目标用户: $TARGET_USER"
REBOOT_HINT=""

echo
echo "=== 0/4 现状 ==="
echo "  运行内核: $(uname -r)"
mod_loaded && echo "  uinput 模块: 已加载" || echo "  uinput 模块: 未加载"

echo
echo "=== 1/4 安装 python-evdev ==="
pacman -S --needed --noconfirm python-evdev || { echo "❌ 安装 python-evdev 失败"; exit 1; }

echo
echo "=== 2/4 uinput 模块开机自动加载 + 本次开机内加载 ==="
echo uinput > /etc/modules-load.d/uinput.conf
if mod_loaded; then
    echo "  模块已加载，跳过"
elif modprobe uinput 2>/dev/null && mod_loaded; then
    echo "  modprobe uinput ✅"
else
    echo "  ⚠️ modprobe 失败（模块目录与运行内核不匹配？），尝试从 pacman 缓存的内核包里取"
    rel="$(uname -r)"; pkgver="${rel/-/.}"
    PKG="$(ls -1 /var/cache/pacman/pkg/linux-${pkgver}-x86_64.pkg.tar.zst 2>/dev/null | tail -1)"
    if [ -n "$PKG" ] && [ -f "$PKG" ]; then
        KO="usr/lib/modules/${rel}/kernel/drivers/input/misc/uinput.ko.zst"
        rm -f /tmp/uinput.ko /tmp/uinput.ko.zst
        if tar --zstd -xOf "$PKG" "$KO" > /tmp/uinput.ko.zst 2>/dev/null && zstd -q -d -f /tmp/uinput.ko.zst -o /tmp/uinput.ko; then
            modinfo /tmp/uinput.ko | grep -E "^(vermagic)" || true
            if insmod /tmp/uinput.ko 2>/dev/null || mod_loaded; then
                echo "  uinput 已在内核里（取自 $PKG；insmod 报 File exists 属正常）✅"
                echo "      仅本次开机有效，重启后由 modules-load.d 自动加载"
            else
                echo "  ❌ 加载失败"; REBOOT_HINT="需要重启一次（重启后会自动加载 uinput）"
            fi
        else
            echo "  ❌ 从内核包里取 uinput.ko 失败"; REBOOT_HINT="需要重启一次"
        fi
    else
        echo "  ❌ 缓存里没有 $pkgver 的内核包"; REBOOT_HINT="需要重启一次（重启后会自动加载 uinput）"
    fi
fi
mod_loaded && echo "  ✅ uinput 已加载" || echo "  ❌ uinput 仍未加载：$REBOOT_HINT"

echo
echo "=== 3/4 udev 规则：把 /dev/uinput 归给 $TARGET_USER ==="
RULE=/etc/udev/rules.d/70-voicetype-uinput.rules
OLD_RULE=/etc/udev/rules.d/99-voicetype-uinput.rules
[ -f "$OLD_RULE" ] && { mv -f "$OLD_RULE" "$RULE"; echo "  已把 99-… 改名成 70-…"; }
[ -f "$RULE" ] && { cp -a "$RULE" "$RULE.bak-$(date +%F-%H%M%S)"; echo "  已有规则，已备份"; }
cat > "$RULE" <<EOF
# VoiceType Desktop：允许用户 $TARGET_USER 使用 /dev/uinput 注入虚拟键盘按键
# OWNER 保证开机时（会话未激活、uaccess ACL 未落）也能写；TAG+="uaccess" 是二次保险
# 文件名必须早于 73-seat-late.rules，TAG 才会被消费成 ACL
KERNEL=="uinput", SUBSYSTEM=="misc", OWNER="$TARGET_USER", MODE="0600", OPTIONS+="static_node=uinput", TAG+="uaccess"
EOF
cat "$RULE"
udevadm control --reload-rules
udevadm trigger --subsystem-match=misc --action=change --settle
sleep 1

echo
echo "=== 4/4 校验（实测：以 $TARGET_USER 身份真的能建虚拟键盘并注入按键） ==="
ls -l /dev/uinput 2>&1
runuser -u "$TARGET_USER" -- python3 - <<'PY'
import os, time
print("/dev/uinput 可写:", "✅" if os.access("/dev/uinput", os.W_OK) else "❌")
try:
    from evdev import UInput, ecodes as e
    keys = [e.KEY_LEFTCTRL, e.KEY_LEFTSHIFT, e.KEY_V, e.KEY_ENTER]
    ui = UInput({e.EV_KEY: keys}, name="voicetype-selftest")
    print("创建/写入虚拟键盘: ✅")
    time.sleep(0.2)
    for code, val in ((e.KEY_LEFTCTRL, 1), (e.KEY_V, 1), (e.KEY_V, 0), (e.KEY_LEFTCTRL, 0)):
        ui.write(e.EV_KEY, code, val); ui.syn()
    ui.close()
    print("注入一次 Ctrl+V: ✅（剪贴板有内容的话，焦点窗口应被粘上）")
except Exception as ex:
    print("❌ 失败:", type(ex).__name__, ex)
PY

echo
echo "=== 自启动检查（用户服务，随图形会话启动） ==="
uid="$(id -u "$TARGET_USER")"
runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user is-enabled voicetype-desktop.service 2>&1 | sed 's/^/  is-enabled: /'
DEPS="$(runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        systemctl --user list-dependencies graphical-session.target --no-pager 2>/dev/null)"
case "$DEPS" in
    *voicetype-desktop*) echo "  ✅ graphical-session.target 依赖里已有 voicetype-desktop（随图形会话自启动）" ;;
    *) echo "  ⚠️ 没挂在 graphical-session.target 上：跑 systemctl --user enable voicetype-desktop" ;;
esac

echo
echo "=== 回滚方法 ==="
echo "  cp -a /etc/udev/rules.d/70-voicetype-uinput.rules.bak-<时间戳> /etc/udev/rules.d/70-voicetype-uinput.rules"
echo "  # 或彻底移除："
echo "  rm -f /etc/udev/rules.d/70-voicetype-uinput.rules /etc/modules-load.d/uinput.conf"
echo "  udevadm control --reload-rules && udevadm trigger"
echo "  rmmod uinput 2>/dev/null            # 本次开机内卸载"
echo "  pacman -Rns python-evdev            # 不再需要 evdev 绑定时"
echo "  rm -f /tmp/uinput.ko /tmp/uinput.ko.zst"
