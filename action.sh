#!/system/bin/sh

# 管理器 action 按钮
MODDIR="$(dirname "$0")"
FSW_MODE=apply exec /system/bin/sh "$MODDIR/service.sh"
