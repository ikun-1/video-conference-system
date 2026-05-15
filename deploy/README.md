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

## 2. 修改配置

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

## 3. 构建并启动

```bash
# 首次构建
docker compose build --no-cache

# 启动全部服务
docker compose up -d
```

启动顺序：MySQL → Redis → 后端（等待 MySQL+Redis 就绪后启动）→ Nginx + TURN

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

## 6. 架构说明

全部容器使用 `host` 网络模式，共享宿主机网络栈：

| 服务 | 镜像 | 端口 | 说明 |
|------|------|------|------|
| mysql | mysql:9 | 3306 | 数据库 |
| redis | redis:7-alpine | 6379 | 缓存 |
| coturn | coturn/coturn | 3478/5349 | TURN/STUN 服务器 |
| backend | 自定义构建 | 8080 | Go/Gin API + WebSocket |
| frontend | 自定义构建 | 80 | Nginx（前端静态文件 + 反向代理 API） |

### 请求流程

```
浏览器 → Nginx(:80) → /api/* → localhost:8080 (后端)
                    → /uploads/* → localhost:8080 (后端静态文件)
                    → /* → index.html (SPA 路由)
```

## 7. 安全注意事项

- 云主机安全组务必**禁止外网访问 3306**（MySQL 直接暴露在 host 网络上）
- 修改所有默认密码后再上线
- 生产环境建议配置 HTTPS（Nginx SSL 终止 + Let's Encrypt）
