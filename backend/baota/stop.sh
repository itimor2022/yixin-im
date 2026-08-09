#!/bin/bash
# 文件用途：baota\stop.sh 是一个后端工具脚本。
# 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。


# 核心逻辑：核心流程：读取 PID，发送优雅停止信号，等待进程退出后清理 PID 文件。
# 通用 IM 后端停止脚本

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
