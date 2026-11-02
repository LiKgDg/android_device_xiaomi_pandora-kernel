#!/usr/bin/env bash
# =============================================================================
# verify.sh — 校验一份自行装配的 pandora-kernel 目录是否与本仓清单一致
#
# 用法：
#   ./verify.sh <path-to-device/xiaomi/pandora-kernel>
#   ./verify.sh /root/los24/device/xiaomi/pandora-kernel
#
# 三步：
#   1) sha256sum -c manifest.sha256        逐文件比对（1112 个）
#   2) 四份 modules.load.* 覆盖率           每一条都能找到对应 .ko
#   3) KMI 世代残留扫描                     vendor 侧不得出现 6.12.23
#
# 退出码：0 = 全过；1 = 有失败；2 = 参数错误
# =============================================================================
set -u

PROG=$(basename "$0")
TARGET=${1:-}

if [ -z "$TARGET" ]; then
    echo "usage: $PROG <path-to-pandora-kernel>" >&2
    exit 2
fi
if [ ! -d "$TARGET" ]; then
    echo "ERROR: not a directory: $TARGET" >&2
    exit 2
fi

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$TARGET" || exit 2
TARGET=$(pwd)
echo "== 目标: $TARGET"
echo "== 清单: $HERE/manifest.sha256"
echo

# ── 1) sha256 ────────────────────────────────────────────────────────────────
echo "== 1/3 sha256 逐文件校验 =="
if sha256sum --quiet -c "$HERE/manifest.sha256" 2>&1; then
    echo "   PASS: 清单内全部文件哈希一致"
else
    echo "   FAIL: 存在哈希不一致或缺失的文件（见上）"
    RC=1
fi
echo

# ── 2) modules.load 覆盖率 ───────────────────────────────────────────────────
echo "== 2/3 modules.load 覆盖率 =="
check_list() {
    local list=$1 m b d hit total=0 miss=0 shown=0
    [ -f "$list" ] || { echo "   SKIP: $list 不存在"; return 0; }
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        case "$m" in \#*) continue ;; esac
        total=$((total + 1))
        hit=0
        if [ -e "$m" ]; then
            hit=1
        else
            b=$(basename "$m")
            for d in vendor_ramdisk vendor_dlkm system_dlkm/kernel system_dlkm_flatten system_dlkm; do
                if [ -e "$d/$b" ]; then hit=1; break; fi
            done
        fi
        if [ "$hit" -eq 0 ]; then
            miss=$((miss + 1))
            if [ "$shown" -lt 5 ]; then
                echo "     MISS $m"
                shown=$((shown + 1))
            fi
        fi
    done < "$list"
    echo "   $(basename "$list"): total=$total missing=$miss"
    [ "$miss" -eq 0 ]
}

LIST_FAIL=0
for l in modules.load.vendor_boot modules.load.recovery \
         modules.load.vendor_dlkm modules.load.system_dlkm; do
    check_list "$HERE/$l" || LIST_FAIL=1
done
[ "$LIST_FAIL" -ne 0 ] && RC=1
echo

# ── 3) KMI 世代残留 ──────────────────────────────────────────────────────────
echo "== 3/3 KMI 世代残留扫描（期望 6.12.69，禁止 6.12.23）=="
if command -v strings >/dev/null 2>&1; then
    scan() {
        local dir=$1 bad=0 n=0 f
        [ -d "$dir" ] || { echo "   SKIP: $dir 不存在"; return 0; }
        for f in "$dir"/*.ko; do
            [ -e "$f" ] || continue
            n=$((n + 1))
            if strings "$f" | grep -q "vermagic=6\.12\.23"; then
                echo "     STALE $f"
                bad=$((bad + 1))
            fi
        done
        echo "   $dir: scanned=$n stale=$bad"
        [ "$bad" -eq 0 ]
    }
    scan vendor_ramdisk || RC=1
    scan vendor_dlkm    || RC=1
else
    echo "   SKIP: 无 strings 命令（装 binutils 后再跑）"
fi
echo

# ── 汇总 ─────────────────────────────────────────────────────────────────────
if [ "${RC:-0}" -eq 0 ]; then
    echo "== 全部通过 =="
    echo "   注意：本脚本只证明『文件与清单一致』，不证明内核可启动。"
    exit 0
else
    echo "== 有失败项，见上 =="
    echo "   常见原因：固件版本不同（本项目基于 OS4.0.5.0.XBLCNXM）、"
    echo "             模块世代错配、或装配时漏拷索引文件。"
    exit 1
fi
