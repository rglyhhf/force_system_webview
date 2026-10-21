#!/system/bin/sh

MODDIR="${0%/*}"
DATA_ROOT=/data/adb/force_webview
CONFIG_FILE=$DATA_ROOT/config.json
MIGRATED_FLAG=$DATA_ROOT/.migrated_v2

mkdir -p $DATA_ROOT/backup $DATA_ROOT/state
chmod 755 $DATA_ROOT $DATA_ROOT/backup $DATA_ROOT/state

# 初始化配置
if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$MODDIR/webroot/config.json" ]; then
        # 复制默认配置
        cp -f "$MODDIR/webroot/config.json" "$CONFIG_FILE"
    elif [ -f "$MODDIR/init_config.json" ]; then
        # 使用初始化配置
        cp -f "$MODDIR/init_config.json" "$CONFIG_FILE"
    else
        # 生成最小初始化配置
        echo '{"apps":{}}' > "$CONFIG_FILE"
    fi

    chmod 644 "$CONFIG_FILE"
fi

# 旧版备份迁移：只按 config dirs 还原，不遍历备份树
if [ ! -f "$MIGRATED_FLAG" ] && [ -n "$(ls -A $DATA_ROOT/backup 2>/dev/null)" ]; then
    OLD_MODE=1 sh "$MODDIR/apply_only.sh" migrate >/dev/null 2>&1
fi

mkdir -p $MODDIR/webroot
cp -f "$CONFIG_FILE" "$MODDIR/webroot/config.json" 2>/dev/null
chmod 644 "$MODDIR/webroot/config.json" 2>/dev/null
