#!/bin/bash
# 文件用途：baota\start.sh 是一个后端工具脚本。
# 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。


# 核心逻辑：核心流程：定位部署目录，检查旧进程和端口状态，写入 PID 后启动服务并输出日志。
# 通用 IM 后端启动脚本
# 用于宝塔面板部署

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    . "$SCRIPT_DIR/.env"
    set +a
fi

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
echo "正在启动通用 IM 后端服务..."
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
