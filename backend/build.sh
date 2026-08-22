#!/bin/bash
# 文件用途：build.sh 是一个后端工具脚本。
# 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。


# 核心逻辑：核心流程：检查构建环境，编译服务和前端资源，整理配置/静态文件并生成部署压缩包。
# ============================================
# 通用IM后端编译脚本
# 用于编译并部署到宝塔目录
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/baota"
BINARY_NAME="server"

# 打印带颜色的消息
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 显示帮助
show_help() {
    echo "用法: ./build.sh [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help      显示帮助信息"
    echo "  -z, --zip       编译后创建 zip 压缩包"
    echo "  -c, --clean     清理旧的编译文件"
    echo "  -a, --all       编译并创建完整部署包（包含配置文件）"
    echo ""
    echo "示例:"
    echo "  ./build.sh           # 仅编译"
    echo "  ./build.sh -z        # 编译并创建 zip"
    echo "  ./build.sh -a        # 创建完整部署包"
}

# 清理
clean() {
    info "清理旧的编译文件..."
    rm -f "$OUTPUT_DIR/$BINARY_NAME"
    rm -f "$OUTPUT_DIR/server.zip"
    rm -f "$OUTPUT_DIR/deploy.zip"
    success "清理完成"
}

# 编译
build() {
    info "开始编译 Go 后端..."
    info "目标平台: Linux amd64"
    
    cd "$SCRIPT_DIR"
    
    # 设置交叉编译环境变量
    export CGO_ENABLED=0
    export GOOS=linux
    export GOARCH=amd64
    
    # 编译
    go build -ldflags="-s -w" -o "$OUTPUT_DIR/$BINARY_NAME" ./cmd/server
    
    if [ -f "$OUTPUT_DIR/$BINARY_NAME" ]; then
        # 获取文件大小
        SIZE=$(ls -lh "$OUTPUT_DIR/$BINARY_NAME" | awk '{print $5}')
        success "编译成功！"
        info "输出文件: $OUTPUT_DIR/$BINARY_NAME"
        info "文件大小: $SIZE"
    else
        error "编译失败，未生成二进制文件"
    fi
}

# 创建 zip 压缩包
create_zip() {
    info "创建 zip 压缩包..."
    
    cd "$OUTPUT_DIR"
    zip -q server.zip "$BINARY_NAME"
    
    if [ -f "server.zip" ]; then
        SIZE=$(ls -lh "server.zip" | awk '{print $5}')
        success "压缩包创建成功！"
        info "输出文件: $OUTPUT_DIR/server.zip"
        info "文件大小: $SIZE"
    else
        error "创建压缩包失败"
    fi
}

# 创建完整部署包
create_deploy_package() {
    info "创建完整部署包..."
    
    cd "$OUTPUT_DIR"
    
    # 创建部署包（包含所有必要文件）
    zip -q deploy.zip \
        "$BINARY_NAME" \
        config.yaml \
        init.sql \
        nginx.conf \
        start.sh \
        stop.sh \
        restart.sh \
        generic-im.service \
        README.md
    
    if [ -f "deploy.zip" ]; then
        SIZE=$(ls -lh "deploy.zip" | awk '{print $5}')
        success "部署包创建成功！"
        info "输出文件: $OUTPUT_DIR/deploy.zip"
        info "文件大小: $SIZE"
        echo ""
        info "部署包内容:"
        unzip -l deploy.zip | tail -n +4 | head -n -2
    else
        error "创建部署包失败"
    fi
}

# 主程序
main() {
    echo ""
    echo "=========================================="
    echo "   通用IM后端编译脚本"
    echo "=========================================="
    echo ""
    
    CREATE_ZIP=false
    CREATE_DEPLOY=false
    DO_CLEAN=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -z|--zip)
                CREATE_ZIP=true
                shift
                ;;
            -c|--clean)
                DO_CLEAN=true
                shift
                ;;
            -a|--all)
                CREATE_DEPLOY=true
                shift
                ;;
            *)
                warn "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 执行操作
    if [ "$DO_CLEAN" = true ]; then
        clean
    fi
    
    build
    
    if [ "$CREATE_ZIP" = true ]; then
        create_zip
    fi
    
    if [ "$CREATE_DEPLOY" = true ]; then
        create_zip
        create_deploy_package
    fi
    
    echo ""
    success "全部完成！"
    echo ""
    info "下一步操作："
    echo "  1. 将 baota/ 目录下的文件上传到服务器"
    echo "  2. 或上传 server.zip / deploy.zip 到服务器解压"
    echo "  3. 执行 ./start.sh 启动服务"
    echo ""
}

main "$@"
