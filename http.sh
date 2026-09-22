#!/bin/bash
set -e

# ==================================================
# Ubuntu HTTP Proxy 一键部署脚本
# Squid + 可选用户名密码认证
# ==================================================

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

# =========================
# 检查 ROOT
# =========================
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行此脚本${NC}"
    exit 1
fi

# =========================
# 检查系统
# =========================
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}无法识别当前系统${NC}"
    exit 1
fi

. /etc/os-release

if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then
    echo -e "${YELLOW}警告：当前系统为 $ID，本脚本主要针对 Ubuntu/Debian。${NC}"
fi

# =========================
# 输入端口
# =========================
read -p "请输入代理端口 [默认 3128]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-3128}

# 检查端口是否合法
if ! [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] || [ "$PROXY_PORT" -lt 1 ] || [ "$PROXY_PORT" -gt 65535 ]; then
    echo -e "${RED}端口不合法，请输入 1-65535 之间的数字。${NC}"
    exit 1
fi

echo ""

# =========================
# 输入账号
# =========================
echo -e "${YELLOW}如果不需要账号密码认证，用户名直接回车即可。${NC}"
read -p "请输入代理用户名 [留空=无需认证]: " PROXY_USER

PROXY_PASS=""

if [ -n "$PROXY_USER" ]; then
    read -s -p "请输入代理密码: " PROXY_PASS
    echo ""

    if [ -z "$PROXY_PASS" ]; then
        echo ""
        echo -e "${YELLOW}密码为空，将自动启用免认证模式。${NC}"
        PROXY_USER=""
    fi
fi

echo ""
echo "=========================================="
echo "配置确认"
echo "=========================================="
echo "代理端口：$PROXY_PORT"

if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
    echo "认证模式：用户名 + 密码"
    echo "用户名：$PROXY_USER"
else
    echo "认证模式：无需认证"
fi

echo "=========================================="
echo ""

# =========================
# 安装
# =========================
export DEBIAN_FRONTEND=noninteractive

echo -e "${CYAN}[1/5] 安装 Squid...${NC}"

apt-get update -y
apt-get install -y squid apache2-utils curl

# =========================
# 备份配置
# =========================
echo -e "${CYAN}[2/5] 备份原配置...${NC}"

if [ -f /etc/squid/squid.conf ]; then
    cp /etc/squid/squid.conf \
       /etc/squid/squid.conf.bak.$(date +%Y%m%d_%H%M%S)
fi

# =========================
# 写配置
# =========================
echo -e "${CYAN}[3/5] 写入代理配置...${NC}"

if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then

    # ----------------------
    # 有认证模式
    # ----------------------

    htpasswd -bc /etc/squid/passwd "$PROXY_USER" "$PROXY_PASS"

    chown proxy:proxy /etc/squid/passwd 2>/dev/null || true
    chmod 640 /etc/squid/passwd

    cat > /etc/squid/squid.conf <<EOFCONF
# ======================================
# Squid HTTP Proxy
# Authentication Enabled
# ======================================

http_port $PROXY_PORT

# DNS
dns_nameservers 1.1.1.1 8.8.8.8

# ----------------------
# 用户认证
# ----------------------
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm HTTP-Proxy
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive on

acl authenticated proxy_auth REQUIRED

# ----------------------
# 允许端口
# ----------------------
acl SSL_ports port 443

acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 21
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535

acl CONNECT method CONNECT

# ----------------------
# 安全规则
# ----------------------
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# 只允许认证用户
http_access allow authenticated

# 其他拒绝
http_access deny all

# ----------------------
# 隐私
# ----------------------
via off
forwarded_for delete

# ----------------------
# 禁止缓存
# ----------------------
cache deny all

# ----------------------
# 日志
# ----------------------
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOFCONF

else

    # ----------------------
    # 无认证模式
    # ----------------------

    rm -f /etc/squid/passwd

    cat > /etc/squid/squid.conf <<EOFCONF
# ======================================
# Squid HTTP Proxy
# Authentication Disabled
# ======================================

http_port $PROXY_PORT

# DNS
dns_nameservers 1.1.1.1 8.8.8.8

# ----------------------
# 允许端口
# ----------------------
acl SSL_ports port 443

acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 21
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535

acl CONNECT method CONNECT

# ----------------------
# 安全规则
# ----------------------
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# 无认证，允许访问
http_access allow all

# ----------------------
# 隐私
# ----------------------
via off
forwarded_for delete

# ----------------------
# 禁止缓存
# ----------------------
cache deny all

# ----------------------
# 日志
# ----------------------
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOFCONF

fi

# =========================
# 验证配置
# =========================
echo -e "${CYAN}[4/5] 检查配置并启动 Squid...${NC}"

if ! squid -k parse; then
    echo ""
    echo -e "${RED}Squid 配置检查失败！${NC}"
    exit 1
fi

systemctl enable squid >/dev/null 2>&1
systemctl restart squid

sleep 2

if ! systemctl is-active --quiet squid; then
    echo -e "${RED}Squid 启动失败。${NC}"
    echo ""
    systemctl status squid --no-pager
    exit 1
fi

# =========================
# 防火墙
# =========================
echo -e "${CYAN}[5/5] 配置防火墙...${NC}"

if command -v ufw >/dev/null 2>&1; then

    if ufw status | grep -q "Status: active"; then
        ufw allow "${PROXY_PORT}/tcp" >/dev/null
        echo "UFW 已放行 TCP/$PROXY_PORT"
    else
        echo "UFW 当前未启用，无需处理。"
    fi

fi

# =========================
# 获取公网 IP
# =========================
PUBLIC_IP=""

PUBLIC_IP=$(curl -4 -s --max-time 5 https://api.ipify.org || true)

if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -4 -s --max-time 5 https://ifconfig.me || true)
fi

if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi

echo ""
echo -e "${GREEN}"
echo "=========================================="
echo "          HTTP Proxy 部署完成"
echo "=========================================="
echo -e "${NC}"

echo "服务器IP：$PUBLIC_IP"
echo "代理端口：$PROXY_PORT"

echo ""

if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then

    echo -e "${GREEN}认证模式：需要用户名密码${NC}"
    echo ""
    echo "用户名：$PROXY_USER"
    echo "密码：$PROXY_PASS"
    echo ""
    echo "代理格式："
    echo ""
    echo "http://$PROXY_USER:$PROXY_PASS@$PUBLIC_IP:$PROXY_PORT"
    echo ""
    echo "IP:PORT 格式："
    echo "$PUBLIC_IP:$PROXY_PORT"
    echo ""
    echo "测试命令："
    echo ""
    echo "curl -x http://$PROXY_USER:$PROXY_PASS@$PUBLIC_IP:$PROXY_PORT https://api.ipify.org"

else

    echo -e "${YELLOW}认证模式：无需用户名密码${NC}"
    echo ""
    echo "代理格式："
    echo ""
    echo "http://$PUBLIC_IP:$PROXY_PORT"
    echo ""
    echo "IP:PORT 格式："
    echo "$PUBLIC_IP:$PROXY_PORT"
    echo ""
    echo "测试命令："
    echo ""
    echo "curl -x http://$PUBLIC_IP:$PROXY_PORT https://api.ipify.org"

fi

echo ""
echo "=========================================="
echo "Squid 服务状态："
echo "=========================================="

systemctl --no-pager --full status squid | head -15

echo ""
echo -e "${YELLOW}提示：如果外部无法连接，请检查云服务器安全组是否放行 TCP/$PROXY_PORT${NC}"

if [ -z "$PROXY_USER" ]; then
    echo ""
    echo -e "${RED}警告：当前为免认证代理。${NC}"
    echo -e "${RED}如果端口直接暴露公网，任何人都可能使用你的代理。${NC}"
    echo -e "${RED}建议在云服务器安全组中仅允许你自己的 IP 访问。${NC}"
fi

echo ""
