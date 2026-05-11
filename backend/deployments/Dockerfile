# 构建阶段
FROM golang:1.21-alpine AS builder

WORKDIR /app

# 安装依赖
RUN apk add --no-cache git ca-certificates

# 复制go mod文件
COPY go.mod go.sum ./
RUN go mod download

# 复制源代码
COPY . .

# 构建
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o server ./cmd/server

# 运行阶段
FROM alpine:3.19

WORKDIR /app

# 安装ca证书
RUN apk --no-cache add ca-certificates tzdata

# 设置时区
ENV TZ=Asia/Shanghai

# 复制二进制文件和配置
COPY --from=builder /app/server .
COPY --from=builder /app/config.yaml .
RUN mkdir -p /app/uploads

# 暴露端口
EXPOSE 8080

# 运行
CMD ["./server"]
