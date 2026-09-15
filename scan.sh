#!/system/bin/sh
# scan.sh — 扫描 /data/data 特征目录和备份区
# 输出: pkg|内核|mstat|特征目录|game|备份MB，最后一行 DONE|未管理数|已管理数

BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=busybox
OUT=/data/adb/modules/force_system_webview/webroot/scan-result.txt
CONFIG=/data/adb/force_webview/config.json
MODROOT=/data/adb/force_webview/backup
TMP=/data/adb/force_webview/.scan-cfg

if [ -z "$WVA_IN_NS" ] && [ -e /proc/1/ns/mnt ]; then
    if [ "$(readlink /proc/$$/ns/mnt 2>/dev/null)" != "$(readlink /proc/1/ns/mnt)" ]; then
        command -v nsenter >/dev/null 2>&1 && WVA_IN_NS=1 exec nsenter --mount=/proc/1/ns/mnt -- /system/bin/sh "$0"
    fi
fi

LOCK=/data/adb/force_webview/.scan-lock
if [ -d "$LOCK" ]; then
    oldpid=$(cat "$LOCK/pid" 2>/dev/null)
    [ -n "$oldpid" ] && [ ! -d "/proc/$oldpid" ] && rm -rf "$LOCK"
fi
if ! mkdir "$LOCK" 2>/dev/null; then
    # 有实例在跑：往 OUT 写 BUSY 标记，前端可识别
    echo "BUSY|$(date +%s)" >> "$OUT"
    exit 1
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT

# config -> pkg<TAB>enabled<TAB>name<TAB>dirs
[ -f "$CONFIG" ] && awk '
    function emit() {
        if (pkg != "") printf "%s\t%s\t%s\t%s\n", pkg, en, nm, dirs
    }
    {
        line = $0
        if (match(line, /^    "[^"]+": \{$/)) {
            emit()
            pkg = line
            gsub(/^    "/, "", pkg); gsub(/": \{$/, "", pkg)
            en = "false"; nm = pkg; dirs = ""; indirs = 0
        }
        else if (pkg != "") {
            if (match(line, /"enabled": (true|false)/)) {
                en = (index(line, "true") > 0) ? "true" : "false"
            }
            else if (match(line, /"name": "[^"]*"/)) {
                nm = line
                gsub(/^.*"name": "/, "", nm); gsub(/",?$/, "", nm)
            }
            else if (index(line, "\"dirs\"") > 0) { indirs = 1 }
            else if (indirs && match(line, /^        "[^"]*",?$/)) {
                d = line
                gsub(/^        "/, "", d); gsub(/",?$/, "", d)
                dirs = dirs (dirs==""?"":" ") d
            }
            else if (line ~ /^[ ]*\]/) { indirs = 0 }
        }
    }
    END { emit() }
' "$CONFIG" > "$TMP" 2>/dev/null || : > "$TMP"

check_features() {
    local d="$1"
    local hits=""
    for sub in $(ls "$d" 2>/dev/null | grep -E '^app_(tbs|u4|x5|xwalk|xweb|meco|r1_webview|webview_mt|h5|webview_d6|extracted_dongCore)'); do
        hits="$hits $sub"
    done
    if [ -d "$d/files" ]; then
        for sub in $(ls "$d/files" 2>/dev/null | grep -E '^(DongCore|WebViewDownloadPlugin|webview_bytedance|mtplatform|mywebview_sdk|myweb_extract|nebulaInstallApps)'); do
            hits="$hits files/$sub"
        done
    fi
    echo "$hits"
}

# 完整内核/组件残留，只对未管理应用做 du
check_kernel() {
    local d="$1"
    local hits="$2"
    for h in $hits; do
        if [ -d "$d/$h" ] && [ -n "$(du -m -d 2 "$d/$h" 2>/dev/null | $BB awk '$1 >= 50 {print; exit}')" ]; then
            echo "完整内核"
            return
        fi
    done
    echo "组件残留"
}

is_game() {
    case "$1" in
        *tmgp*|*mihoyo*|*MiHoYo*|*hypergryph*|*kurogame*|*yostar*|*YoStar*|*yo-star*|\
        *garena*|*gameloft*|*epicgames*|*riotgames*|*krafton*|*blizzard*|\
        *.game|*.games|*gamecenter*|*mobilelegends*)
            echo "game";;
        *) echo "";;
    esac
}

: > "$OUT"
echo "STARTED|$$|$(date +%s)" >> "$OUT"
u=0; m=0

for d in /data/data/*/; do
    pkg="${d%/}"; pkg="${pkg##*/}"
    case "$pkg" in _*) continue;; esac

    [ -n "$(ls -A "$MODROOT/$pkg" 2>/dev/null)" ] && continue

    hits=$(check_features "$d")
    [ -z "$hits" ] && continue

    gtag=$(is_game "$pkg")
    if awk -F'\t' -v p="$pkg" '$1==p{found=1} END{exit !found}' "$TMP" 2>/dev/null; then
            m=$((m+1))
        echo "$pkg|未管控|已配置|$hits|$gtag|0" >> "$OUT"
    else
        u=$((u+1))
        kernel=$(check_kernel "$d" "$hits")
        echo "$pkg|$kernel|未管理|$hits|$gtag|0" >> "$OUT"
    fi
done

for pkg in $(ls "$MODROOT" 2>/dev/null); do
    [ -d "$MODROOT/$pkg" ] || continue
    dirs=$(awk -F'\t' -v p="$pkg" '$1==p{print $4; exit}' "$TMP" 2>/dev/null)
    [ -z "$dirs" ] && dirs=$(ls "$MODROOT/$pkg" 2>/dev/null | tr '\n' ' ')
    bk=$(du -sm "$MODROOT/$pkg" 2>/dev/null | cut -f1)
    [ -z "$bk" ] && bk=0
    gtag=$(is_game "$pkg")
    m=$((m+1))
    echo "$pkg|管控中|已生效|$dirs|$gtag|$bk" >> "$OUT"
done

rm -f "$TMP"
echo "DONE|$u|$m" >> "$OUT"
