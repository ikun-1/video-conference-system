# TURN服务器部署指南

## 1. 安装coturn（推荐使用Ubuntu服务器）

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装coturn
sudo apt install coturn -y

# 启用coturn服务
sudo systemctl enable coturn
```

## 2. 配置coturn

编辑配置文件：
```bash
sudo nano /etc/turnserver.conf
```

### 基础配置

```conf
# TURN服务器监听端口
listening-port=3478
tls-listening-port=5349

# 外部IP地址（你的服务器公网IP）
external-ip=YOUR_SERVER_PUBLIC_IP

# 中继IP范围
relay-ip=YOUR_SERVER_PUBLIC_IP

# 认证域
realm=your-domain.com

# 日志
verbose
log-file=/var/log/turnserver.log

# 使用长期凭证机制
lt-cred-mech

# 用户认证（用户名:密码）
user=turnuser:turnpassword

# 或使用数据库认证
# psql-userdb="host=localhost dbname=coturn user=coturn password=yourpassword"

# 限制
max-bps=1000000
bps-capacity=0

# 允许的对等地址范围
no-tcp-relay
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255

# 允许的客户端地址（可选，限制只有你的应用可以使用）
# allowed-peer-ip=YOUR_APP_SERVER_IP

# 证书（用于TLS）
# cert=/etc/letsencrypt/live/your-domain.com/fullchain.pem
# pkey=/etc/letsencrypt/live/your-domain.com/privkey.pem

# 性能优化
no-multicast-peers
no-cli
```

### 生成强密码

```bash
# 生成随机密码
openssl rand -base64 32
```

## 3. 配置防火墙

```bash
# 允许TURN端口
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
sudo ufw allow 5349/tcp
sudo ufw allow 5349/udp

# 允许中继端口范围（49152-65535）
sudo ufw allow 49152:65535/tcp
sudo ufw allow 49152:65535/udp

# 重新加载防火墙
sudo ufw reload
```

## 4. 启动服务

```bash
# 启动coturn
sudo systemctl start coturn

# 查看状态
sudo systemctl status coturn

# 查看日志
sudo tail -f /var/log/turnserver.log
```

## 5. 测试TURN服务器

使用在线工具测试：
- https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/

配置：
```
TURN URI: turn:your-server-ip:3478
Username: turnuser
Password: turnpassword
```

## 6. 使用SSL/TLS（推荐生产环境）

```bash
# 安装certbot
sudo apt install certbot -y

# 获取证书（需要域名）
sudo certbot certonly --standalone -d turn.your-domain.com

# 配置自动续期
sudo certbot renew --dry-run
```

更新turnserver.conf：
```conf
cert=/etc/letsencrypt/live/turn.your-domain.com/fullchain.pem
pkey=/etc/letsencrypt/live/turn.your-domain.com/privkey.pem
```

## 7. 性能优化

### 系统限制

编辑 `/etc/security/limits.conf`：
```
* soft nofile 65536
* hard nofile 65536
```

### 内核参数

编辑 `/etc/sysctl.conf`：
```
net.ipv4.ip_local_port_range = 10000 65535
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
```

应用：
```bash
sudo sysctl -p
```

## 8. 监控和维护

### 查看连接数
```bash
sudo netstat -anp | grep turnserver | wc -l
```

### 查看日志
```bash
sudo journalctl -u coturn -f
```

### 重启服务
```bash
sudo systemctl restart coturn
```

## 9. Docker部署（可选）

```yaml
# docker-compose.yml
version: '3'
services:
  coturn:
    image: coturn/coturn:latest
    network_mode: host
    volumes:
      - ./turnserver.conf:/etc/coturn/turnserver.conf
    restart: unless-stopped
```

启动：
```bash
docker-compose up -d
```

## 10. 成本估算

### 云服务器推荐配置
- CPU: 2核
- 内存: 4GB
- 带宽: 5Mbps+（根据并发用户数调整）
- 存储: 20GB

### 带宽计算
- 每个用户约需要 1-2 Mbps
- 10个并发用户：10-20 Mbps
- 建议预留50%余量

### 价格参考（月付）
- 阿里云：约100-200元/月
- 腾讯云：约100-200元/月
- AWS：约$15-30/月

## 常见问题

### Q: TURN服务器和应用服务器可以在同一台机器吗？
A: 可以，但建议分开部署以提高性能和安全性。

### Q: 需要多少带宽？
A: 每个视频通话约1-2Mbps，根据最大并发用户数计算。

### Q: 如何限制只有我的应用可以使用？
A: 使用 `allowed-peer-ip` 限制客户端IP，或使用动态凭证。

### Q: 如何实现动态凭证？
A: 使用REST API生成临时用户名和密码，参考coturn文档。
