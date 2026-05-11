#!/bin/bash

# 壹信 IM 后端重启脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "正在重启服务..."
"$SCRIPT_DIR/stop.sh"
sleep 1
"$SCRIPT_DIR/start.sh"
