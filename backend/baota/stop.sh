#!/bin/bash

# 壹信 IM 后端停止脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/server.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "PID 文件不存在，服务可能未运行"
    exit 0
fi

PID=$(cat "$PID_FILE")

if ps -p "$PID" > /dev/null 2>&1; then
    echo "正在停止服务 (PID: $PID)..."
    kill "$PID"
    sleep 2
    
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "服务未响应，强制终止..."
        kill -9 "$PID"
    fi
    
    rm -f "$PID_FILE"
    echo "服务已停止"
else
    echo "服务未运行"
    rm -f "$PID_FILE"
fi
