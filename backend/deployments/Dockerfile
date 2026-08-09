# 文件用途：deployments\Dockerfile 是一个Dockerfile 容器构建文件。
# 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

FROM golang:1.24-alpine AS builder

WORKDIR /app

ARG ALPINE_MIRROR="https://mirrors.aliyun.com/alpine"
ARG GOPROXY="https://goproxy.cn,direct"
ENV GOPROXY=${GOPROXY}

RUN if [ -n "$ALPINE_MIRROR" ]; then \
      sed -i "s|https://dl-cdn.alpinelinux.org/alpine|$ALPINE_MIRROR|g" /etc/apk/repositories; \
    fi
RUN apk add --no-cache git ca-certificates

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o server ./cmd/server

FROM alpine:3.19

WORKDIR /app

ENV TZ=Asia/Shanghai

COPY --from=builder /app/server .
COPY --from=builder /app/config.yaml .
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN apk add --no-cache ffmpeg libheif-tools && \
    mkdir -p /app/uploads

EXPOSE 8080

CMD ["./server"]
