#!/system/bin/sh

# uninstall.sh — 按 config dirs 还原备份后清理

DATA_ROOT=/data/adb/force_webview
CONFIG_FILE=$DATA_ROOT/config.json
BACKUP_ROOT=$DATA_ROOT/backup
LOCK_DIR=$DATA_ROOT/.lockdir
TAB=$(printf '\t')

parse_config() {
    awk '
    function emit() {
        if (pkg != "") {
            for (i=1; i<=dcount; i++) print pkg "\t" dirs[i]
            if (dcount == 0) print pkg "\t"
        }
    }
    {
        line = $0
        if (match(line, /^    "[^"]+": \{$/)) {
            emit()
            pkg = line
            gsub(/^    "/, "", pkg); gsub(/": \{$/, "", pkg)
            dcount = 0; indirs = 0
        }
        else if (pkg != "") {
            if (index(line, "\"dirs\"") > 0) { indirs = 1 }
            else if (indirs && match(line, /^        "[^"]*",?$/)) {
                d = line
                gsub(/^        "/, "", d); gsub(/",?$/, "", d)
                dirs[++dcount] = d
            }
            else if (line ~ /^[ ]*\]/) { indirs = 0 }
        }
    }
    END { emit() }
    ' "$CONFIG_FILE"
}

restore_all() {
    [ -f "$CONFIG_FILE" ] || { echo "无配置，跳过"; return 0; }

    parse_config | while IFS="$TAB" read -r pkg rel; do
        [ -z "$pkg" ] && continue
        [ -d "/data/data/$pkg" ] || continue

        if [ -n "$rel" ] && [ -e "$BACKUP_ROOT/$pkg/$rel" ]; then
            dst="/data/data/$pkg/$rel"
            if [ -e "$dst" ]; then
                chmod 755 "$dst" 2>/dev/null
                rm -rf "$dst" 2>/dev/null
            fi
            if [ ! -e "$dst" ]; then
                mkdir -p "$(dirname "$dst")"
                if mv "$BACKUP_ROOT/$pkg/$rel" "$dst" 2>/dev/null; then
                    appu=$(stat -c "%U:%G" "/data/data/$pkg" 2>/dev/null)
                    ctx=$(ls -Zd "/data/data/$pkg" 2>/dev/null | awk '{print $1}')
                    [ -n "$appu" ] && chown -R "$appu" "$dst" 2>/dev/null
                    [ -n "$ctx" ] && chcon -R "$ctx" "$dst" 2>/dev/null
                    echo "已还原 $pkg/$rel"
                else
                    echo "还原失败 $pkg/$rel"
                fi
            fi
        fi
    done
}

mkdir -p "$DATA_ROOT"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$pid" ] && [ ! -d "/proc/$pid" ]; then
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR" 2>/dev/null || { echo "模块正在运行，请稍后再试"; exit 1; }
    else
        echo "模块正在运行，请稍后再试"
        exit 1
    fi
fi

echo "开始还原备份..."
restore_all

echo "删除 /data/adb/force_webview ..."
rm -rf "$DATA_ROOT"
echo "卸载完成（模块自身的目录由管理器删除）"
