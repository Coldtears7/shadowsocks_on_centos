#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear

echo -e "${CYAN}"
echo "=========================================="
echo "       Ubuntu HTTP Proxy 一键部署"
echo "=========================================="
echo -e "${NC}"

# ==========================================
# ROOT 检查
# ==========================================
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行此脚本${NC}"
    exit 1
fi

# ==========================================
# 系统检查
# ==========================================
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}无法识别当前系统${NC}"
    exit 1
fi

. /etc/os-release

if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then
    echo -e "${YELLOW}警告：当前系统为 $ID，本脚本主要针对 Ubuntu/Debian。${NC}"
fi

# ==========================================
# 输入代理监听端口
# ==========================================
read -p "请输入代理端口 [默认 3128]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-3128}

if ! [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] || \
   [ "$PROXY_PORT" -lt 1 ] || \
   [ "$PROXY_PORT" -gt 65535 ]; then

    echo -e "${RED}端口不合法，请输入 1-65535。${NC}"
    exit 1
fi

echo ""

# ==========================================
# 输入用户名密码
# ==========================================
echo -e "${YELLOW}如果不需要认证，用户名直接回车即可。${NC}"

read -p "请输入代理用户名 [留空=无需认证]: " PROXY_USER

PROXY_PASS=""

if [ -n "$PROXY_USER" ]; then

    read -s -p "请输入代理密码 [留空=无需认证]: " PROXY_PASS
    echo ""

    if [ -z "$PROXY_PASS" ]; then
        echo -e "${YELLOW}密码为空，自动切换为免认证模式。${NC}"
        PROXY_USER=""
    fi
fi

echo ""
echo "=========================================="
echo "配置确认"
echo "=========================================="
echo "监听端口：$PROXY_PORT"
echo "目标端口：全部开放"

if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
    echo "认证模式：用户名 + 密码"
    echo "用户名：$PROXY_USER"
else
    echo "认证模式：无需认证"
fi

echo "=========================================="
echo ""

# ==========================================
# 安装软件
# ==========================================
export DEBIAN_FRONTEND=noninteractive

echo -e "${CYAN}[1/5] 安装 Squid...${NC}"

apt-get update -y
apt-get install -y squid apache2-utils curl

# ==========================================
# 备份旧配置
# ==========================================
echo -e "${CYAN}[2/5] 备份原配置...${NC}"

if [ -f /etc/squid/squid.conf ]; then

    cp /etc/squid/squid.conf \
       "/etc/squid/squid.conf.bak.$(date +%Y%m%d_%H%M%S)"

fi

# ==========================================
# 配置 Squid
# ==========================================
echo -e "${CYAN}[3/5] 写入代理配置...${NC}"

if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then

    # ======================================
    # 认证模式
    # ======================================

    htpasswd -bc /etc/squid/passwd \
        "$PROXY_USER" \
        "$PROXY_PASS"

    chown proxy:proxy /etc/squid/passwd 2>/dev/null || true
    chmod 640 /etc/squid/passwd

    cat > /etc/squid/squid.conf <<EOFCONF
# ==========================================
# Squid HTTP Proxy
# Authentication Enabled
# All destination ports allowed
# ==========================================

http_port 0.0.0.0:$PROXY_PORT

# DNS
dns_nameservers 1.1.1.1 8.8.8.8

# ==========================================
# Basic Authentication
# ==========================================

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm HTTP-Proxy
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive on

acl authenticated proxy_auth REQUIRED

# ==========================================
# Access
#
# 不限制目标端口
# 不限制 CONNECT 目标端口
# 认证成功即可使用
# ==========================================

http_access allow authenticated
http_access deny all

# ==========================================
# Privacy
# ==========================================

forwarded_for delete

# ==========================================
# Disable cache
# ==========================================

cache deny all

# ==========================================
# Logs
# ==========================================

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOFCONF

else

    # ======================================
    # 无认证模式
    # ======================================

    rm -f /etc/squid/passwd

    cat > /etc/squid/squid.conf <<EOFCONF
# ==========================================
# Squid HTTP Proxy
# Authentication Disabled
# All destination ports allowed
# ==========================================

http_port 0.0.0.0:$PROXY_PORT

# DNS
dns_nameservers 1.1.1.1 8.8.8.8

# ==========================================
# Access
#
# 无认证
# 不限制目标端口
# 不限制 CONNECT 目标端口
# ==========================================

http_access allow all

# ==========================================
# Privacy
# ==========================================

forwarded_for delete

# ==========================================
# Disable cache
# ==========================================

cache deny all

# ==========================================
# Logs
# ==========================================

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOFCONF

fi

# ==========================================
# 检查配置
# ==========================================
echo -e "${CYAN}[4/5] 检查配置并启动 Squid...${NC}"

if ! squid -k parse; then

    echo ""
    echo -e "${RED}Squid 配置检查失败！${NC}"
    exit 1

fi

systemctl enable squid >/dev/null 2>&1 || true
systemctl restart squid

sleep 2

if ! systemctl is-active --quiet squid; then

    echo -e "${RED}Squid 启动失败。${NC}"
    echo ""

    systemctl status squid --no-pager

    exit 1
fi

# ==========================================
# UFW
# ==========================================
echo -e "${CYAN}[5/5] 配置防火墙...${NC}"

if command -v ufw >/dev/null 2>&1; then

    if ufw status | grep -q "Status: active"; then

        ufw allow "${PROXY_PORT}/tcp" >/dev/null

        echo "UFW 已放行 TCP/$PROXY_PORT"

    else

        echo "UFW 当前未启用，无需处理。"

    fi

fi

# ==========================================
# 获取公网 IPv4
# ==========================================
PUBLIC_IP=""

PUBLIC_IP=$(curl -4 -s --max-time 5 \
    https://api.ipify.org || true)

if [ -z "$PUBLIC_IP" ]; then

    PUBLIC_IP=$(curl -4 -s --max-time 5 \
        https://ifconfig.me || true)

fi

if [ -z "$PUBLIC_IP" ]; then

    PUBLIC_IP=$(hostname -I | awk '{print $1}')

fi

# ==========================================
# 输出结果
# ==========================================
echo ""
echo -e "${GREEN}"
echo "=========================================="
echo "          HTTP Proxy 部署完成"
echo "=========================================="
echo -e "${NC}"

echo "服务器IP：$PUBLIC_IP"
echo "代理端口：$PROXY_PORT"
echo "目标端口：全部开放"
echo ""

if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then

    echo -e "${GREEN}认证模式：用户名 + 密码${NC}"
    echo ""

    echo "用户名：$PROXY_USER"
    echo "密码：$PROXY_PASS"

    echo ""
    echo "代理地址："
    echo ""
    echo "http://$PROXY_USER:$PROXY_PASS@$PUBLIC_IP:$PROXY_PORT"

    echo ""
    echo "IP:PORT："
    echo "$PUBLIC_IP:$PROXY_PORT"

    echo ""
    echo "HTTP 测试："
    echo ""
    echo "curl -x http://$PROXY_USER:$PROXY_PASS@$PUBLIC_IP:$PROXY_PORT http://api.ipify.org"

    echo ""
    echo "HTTPS 测试："
    echo ""
    echo "curl -x http://$PROXY_USER:$PROXY_PASS@$PUBLIC_IP:$PROXY_PORT https://api.ipify.org"

else

    echo -e "${YELLOW}认证模式：无需认证${NC}"

    echo ""
    echo "代理地址："
    echo ""
    echo "http://$PUBLIC_IP:$PROXY_PORT"

    echo ""
    echo "IP:PORT："
    echo "$PUBLIC_IP:$PROXY_PORT"

    echo ""
    echo "HTTP 测试："
    echo ""
    echo "curl -x http://$PUBLIC_IP:$PROXY_PORT http://api.ipify.org"

    echo ""
    echo "HTTPS 测试："
    echo ""
    echo "curl -x http://$PUBLIC_IP:$PROXY_PORT https://api.ipify.org"

fi

echo ""
echo "=========================================="
echo "监听状态"
echo "=========================================="

ss -lntp | grep ":$PROXY_PORT" || true

echo ""
echo "=========================================="
echo "Squid 状态"
echo "=========================================="

systemctl --no-pager --full status squid | head -15

echo ""

if [ -z "$PROXY_USER" ]; then

    echo -e "${RED}注意：当前代理为免认证 + 全目标端口开放。${NC}"
    echo -e "${RED}如果直接暴露公网，任何人都可以使用。${NC}"

fi

echo ""
echo "日志查看："
echo ""
echo "tail -f /var/log/squid/access.log"

echo ""
