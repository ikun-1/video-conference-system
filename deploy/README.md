# 部署指南

## 前置条件

- 云主机（Ubuntu/Debian 推荐）
- 已安装 Docker

```bash
curl -fsSL https://get.docker.com | bash -s docker
sudo usermod -aG docker $USER
# 退出重新登录使组生效
```

## 1. 把项目传到云主机

```bash
git clone <你的仓库地址> graduation_project
cd graduation_project/video-conference-system/deploy
```

或通过 `scp` 手动传输。

## 2. 一键部署脚本（推荐）

> **前置：** 仅需修改 TURN 服务器地址（因为 Docker 使用 host 网络模式，MySQL/Redis 等通过 `127.0.0.1` 即可通信）

```bash
#!/bin/bash
# deploy.sh - 云服务器一键部署脚本

set -e

# 修改这个值为你的云主机公网 IP
SERVER_IP=${1:-"127.0.0.1"}

echo ">>> 使用服务器 IP: $SERVER_IP"

# 修改 TURN 配置
echo ">>> 更新 TURN 服务器地址..."
sed -i "s/external-ip=.*/external-ip=$SERVER_IP/g" turnserver.conf
sed -i "s/relay-ip=.*/relay-ip=$SERVER_IP/g" turnserver.conf

# 修改 WebRTC ICE 服务器地址
echo ">>> 更新 WebRTC ICE 服务器地址..."
sed -i "s/turn:localhost/turn:$SERVER_IP/g" settings.yaml
sed -i "s/turn:127.0.0.1/turn:$SERVER_IP/g" settings.yaml

# 构建并启动
echo ">>> 构建镜像（首次可能需要 3-5 分钟）..."
docker compose build --no-cache

echo ">>> 启动所有服务..."
docker compose up -d

echo ">>> 等待服务就绪（约 30-60 秒）..."
sleep 30

echo ">>> 服务状态:"
docker compose ps

echo ""
echo "✅ 部署完成！"
echo "   访问应用: http://$SERVER_IP"
echo "   查看日志: docker compose logs -f"
```

**使用方式：**

```bash
# 下载脚本后赋予执行权限
chmod +x deploy.sh

# 一键部署（替换成你的实际公网 IP）
./deploy.sh 123.45.67.89
```

或者手动修改配置：

## 2. 手动修改配置

### 2.1 TURN 地址

编辑 `settings.yaml`，把 TURN 地址改为云主机公网 IP：

```yaml
webrtc:
  ice_servers:
    - urls:
        - "turn:你的云主机公网IP:3478"
      username: "devuser"
      credential: "devpassword"
```

编辑 `turnserver.conf`，同步修改：

```
external-ip=你的云主机公网IP
relay-ip=你的云主机公网IP
```

### 2.2 （可选）修改默认密码

生产环境建议修改以下默认值：

- `settings.yaml` → `db.password`
- `settings.yaml` → `jwt.key`
- `settings.yaml` → `webrtc[].credential`
- `turnserver.conf` → `user=用户名:密码`

MySQL 密码可以通过环境变量覆盖：

```bash
MYSQL_PASSWORD="你的密码" docker compose up -d
```

### 2.3 Host 网络模式说明

当前 `docker-compose.yml` 所有容器都使用 `network_mode: host`：

✅ **优点：**

- 容器内 `127.0.0.1` = 宿主机 localhost → MySQL、Redis 无需改 IP
- 网络性能最优（无网络隔离开销）

⚠️ **注意：**

- 所有容器端口直接暴露到宿主机
- 容器之间通过 `127.0.0.1` 通信
- TURN 服务需要真实公网 IP（不能用 localhost）

### 2.4 HTTPS 配置（可选）

当前 Nginx 已配置 HTTPS（443 端口），用自签名证书。

**云服务器部署流程（完整）：**

```bash
# 1. 拉取代码后进入 deploy 目录
git clone <你的仓库地址>
cd video-conference-system/deploy

# 2. 生成自签名证书（二选一）
# 方式 1: 运行 sh 脚本（推荐 Linux/macOS）
chmod +x generate-cert.sh
./generate-cert.sh 123.45.67.89

# 方式 2: 直接用 openssl 命令（Linux/macOS）
openssl req -x509 -newkey rsa:2048 -keyout certs/server.key -out certs/server.crt -days 365 -nodes -subj "/CN=123.45.67.89"
```

**参数说明：**

- `123.45.67.89` — 替换成你的云服务器公网 IP 或域名
- `certs/server.crt` — 生成的证书文件
- `certs/server.key` — 生成的私钥文件
- `365` — 证书有效期（天数）

**证书文件说明：**

- `/certs/server.crt` — 证书（自动挂载到 Nginx）
- `/certs/server.key` — 私钥（自动挂载到 Nginx）

**HTTPS 访问：**

```
https://123.45.67.89
# 浏览器会提示"此证书不受信任"
# 点击"继续访问" 或 "接受风险" 继续
```

**生产环境建议（使用 Let's Encrypt）：**

- 购买真实域名
- 使用 Let's Encrypt 签发免费证书

```bash
# 需要 certbot
sudo apt-get install certbot python3-certbot-nginx

# 生成证书（需要 DNS 解析已指向该服务器）
sudo certbot certonly --nginx -d your-domain.com

# 修改 nginx.conf 中的证书路径指向 Let's Encrypt 的证书
```

## 3. 构建并启动

```bash
# 首次构建（包含依赖下载和编译）
docker compose build --no-cache

# 启动全部服务
docker compose up -d
```

启动顺序：MySQL → Redis → 后端（等待 MySQL+Redis 就绪后启动）→ Nginx + TURN

### 3.1 构建过程说明

**后端（Go）：**

- 多阶段构建
- Stage 1: 编译
  - 下载 `go.mod` 和 `go.sum` 中的所有依赖（`go mod download`）
  - 编译 Go 源代码为 Linux 二进制文件
- Stage 2: 运行环境
  - 最小化镜像（仅包含 ffmpeg、ca-certificates 等必需工具）
  - 复制二进制文件和初始化脚本

**前端（Vue + TypeScript）：**

- 多阶段构建
- Stage 1: 构建
  - 安装 npm 依赖（`npm ci` - 根据 `package-lock.json` 安装精确版本）
  - 运行 `npm run build-only` 编译前端资源
- Stage 2: 运行环境
  - 最小化镜像（仅 Nginx）
  - 复制编译后的 dist 文件

**为什么不需要在宿主机安装 Go/Node.js？**

- 所有编译都在 Docker 容器内完成
- `go mod download` = Go 依赖锁定
- `npm ci` = Node 依赖锁定（vs `npm install`）
- 宿主机仅需 Docker & Docker Compose

## 4. 验证

```bash
# 查看各服务状态
docker compose ps

# 查看启动日志
docker compose logs -f

# 检查 MySQL 是否就绪
docker compose logs mysql | tail -5
# 期望输出: "/usr/sbin/mysqld: ready for connections."

# 检查后端是否就绪（首次启动需等待 30-60 秒数据库初始化）
docker compose logs backend | tail -5
# 期望输出: "后端服务运行在 0.0.0.0:8080"

# 测试 API
curl http://localhost/api/meetings?page=1\&limit=1

# 测试前端
curl -s http://localhost | head -1
# 期望输出: "<!DOCTYPE html>..."
```

浏览器访问 `http://你的云主机IP` 即可打开应用。

## 5. 日常操作

```bash
# 查看日志
docker compose logs -f backend
docker compose logs -f frontend

# 重启某个服务
docker compose restart backend

# 更新代码后重新构建
docker compose build backend frontend
docker compose up -d

# 停止所有服务
docker compose down

# 停止并删除数据卷（会丢失数据库和 Redis 数据）
docker compose down -v
```

### 5.1 数据备份

**备份 MySQL：**

```bash
docker exec -i video-conference-mysql sh -c 'exec mysqldump --all-databases -uroot -p"${MYSQL_PASSWORD:-88888888}"' > backup-$(date +%Y%m%d).sql
```

**备份卷数据：**

```bash
docker run --rm -v video-conference-mysql:/data -v $PWD:/backup busybox tar czf /backup/mysql-data-$(date +%Y%m%d).tar.gz -C /data .
```

## 6. 故障排查

### 后端启动失败

```bash
docker compose logs backend --tail 50

# 常见原因：
# 1. MySQL 未就绪 → 等待 30-60 秒，查看数据库初始化日志
# 2. Redis 连接失败 → 检查 Redis 容器是否运行
# 3. TURN 配置错误 → 检查 ice_servers 地址和凭证
```

**解决：**

```bash
# 重新初始化数据库和 RBAC
docker compose exec backend ./fast-gin -f /app/config/settings.yaml -db
docker compose exec backend ./fast-gin -f /app/config/settings.yaml -m rbac -t init

# 重启后端
docker compose restart backend
```

### 前端无法访问

```bash
# 检查 Nginx 是否运行
docker compose ps frontend

# 检查 Nginx 日志
docker compose logs frontend --tail 50

# 检查是否监听 80 端口
netstat -tlnp | grep 80  # Linux
# 或
lsof -i :80  # macOS/Linux
```

### WebRTC 连接失败

```bash
# 检查 TURN 服务器状态
docker compose logs coturn --tail 50

# 检查 TURN 地址是否正确（必须是公网 IP，不能是 localhost）
grep -i "turn:" settings.yaml
grep -i "external-ip" turnserver.conf
```

### 容器大量日志占用磁盘

Docker 日志驱动配置了 `max-size: 10m` 和 `max-file: 3`，单个服务最多占用 30MB。

清理旧日志：

```bash
docker system prune --all -f
```

## 7. 架构说明

全部容器使用 `host` 网络模式，共享宿主机网络栈：

| 服务     | 镜像           | 端口      | 说明                                 |
| -------- | -------------- | --------- | ------------------------------------ |
| mysql    | mysql:9        | 3306      | 数据库                               |
| redis    | redis:7-alpine | 6379      | 缓存                                 |
| coturn   | coturn/coturn  | 3478/5349 | TURN/STUN 服务器                     |
| backend  | 自定义构建     | 8080      | Go/Gin API + WebSocket               |
| frontend | 自定义构建     | 80        | Nginx（前端静态文件 + 反向代理 API） |

### 请求流程

```
浏览器 → Nginx(:80) → /api/* → localhost:8080 (后端)
                    → /uploads/* → localhost:8080 (后端静态文件)
                    → /* → index.html (SPA 路由)
```

## 8. 安全注意事项

- 云主机安全组务必**禁止外网访问 3306**（MySQL 直接暴露在 host 网络上）
- 修改所有默认密码后再上线
- 生产环境建议配置 HTTPS（Nginx SSL 终止 + Let's Encrypt）
- 定期备份 MySQL 数据
- 监控 Docker 日志磁盘占用（已配置自动轮转）
- 限制 WebRTC 最大参会人数（`settings.yaml` → `webrtc.max_participants`）
