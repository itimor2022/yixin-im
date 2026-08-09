#!/bin/bash
# 文件用途：baota\restart.sh 是一个后端工具脚本。
# 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。


# 核心逻辑：核心流程：定位部署目录，检查旧进程和端口状态，写入 PID 后启动服务并输出日志。
# 通用 IM 后端重启脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "正在重启服务..."
"$SCRIPT_DIR/stop.sh"
sleep 1
"$SCRIPT_DIR/start.sh"
