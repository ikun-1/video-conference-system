# Stage 1: 编译 Go 二进制
FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY video-conference-backend/go.mod video-conference-backend/go.sum ./
ENV GOPROXY=https://goproxy.cn,direct
RUN go mod download

COPY video-conference-backend/ .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o fast-gin main.go

# Stage 2: 运行环境
FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata ffmpeg

WORKDIR /app
COPY --from=builder /build/fast-gin .

RUN mkdir -p uploads/images recordings logs

EXPOSE 8080

COPY <<-"EOF" /app/docker-entrypoint.sh
	#!/bin/sh
	set -e
	echo ">>> 执行数据库迁移..."
	./fast-gin -f /app/config/settings.yaml -db
	echo ">>> 启动后端服务..."
	exec ./fast-gin -f /app/config/settings.yaml
EOF
RUN chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
