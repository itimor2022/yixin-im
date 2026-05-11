#!/bin/bash

# 壹信 IM 后端启动脚本
# 用于宝塔面板部署

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 检查是否已经运行
PID_FILE="$SCRIPT_DIR/server.pid"
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "服务已在运行 (PID: $OLD_PID)"
        exit 1
    fi
fi

# 启动服务
echo "正在启动壹信 IM 后端服务..."
nohup ./server > "$SCRIPT_DIR/server.log" 2>&1 &
NEW_PID=$!
echo $NEW_PID > "$PID_FILE"

sleep 2

if ps -p "$NEW_PID" > /dev/null 2>&1; then
    echo "服务启动成功 (PID: $NEW_PID)"
    echo "日志文件: $SCRIPT_DIR/server.log"
else
    echo "服务启动失败，请查看日志文件"
    cat "$SCRIPT_DIR/server.log"
    exit 1
fi
