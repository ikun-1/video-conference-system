#!/bin/bash
# 生成自签名证书脚本
# 用法: ./generate-cert.sh 123.45.67.89
#   或: ./generate-cert.sh your-domain.com

set -e

# 获取参数（IP 或域名）
TARGET=${1:-"localhost"}

# 证书输出目录
CERT_DIR="$(cd "$(dirname "$0")" && pwd)/certs"
mkdir -p "$CERT_DIR"

CERT_FILE="$CERT_DIR/server.crt"
KEY_FILE="$CERT_DIR/server.key"

echo ">>> 生成自签名证书..."
echo "    目标: $TARGET"
echo "    证书: $CERT_FILE"
echo "    密钥: $KEY_FILE"

# 生成自签名证书（有效期 365 天）
openssl req -x509 \
  -newkey rsa:2048 \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  -days 365 \
  -nodes \
  -subj "/CN=$TARGET" \
  -addext "subjectAltName=IP:$TARGET,DNS:$TARGET"

echo "✅ 证书生成成功！"
echo ""
echo "证书信息："
openssl x509 -in "$CERT_FILE" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After|CN=|Subject Alternative)" || true
