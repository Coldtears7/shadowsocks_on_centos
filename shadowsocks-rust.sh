#!/usr/bin/env bash
# Shadowsocks-Rust 一键安装脚本，适用于 Ubuntu/Debian 与现代 RHEL 系统

set -Eeuo pipefail

readonly VERSION="v1.25.0"
readonly BASE_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${VERSION}"
readonly BIN_FILE="/usr/local/bin/ssserver"
readonly CONFIG_DIR="/etc/shadowsocks-rust"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly SERVICE_FILE="/etc/systemd/system/shadowsocks-rust.service"
readonly SERVICE_NAME="shadowsocks-rust.service"
readonly SERVICE_USER="shadowsocks-rust"
readonly LOG_TAG="奶子哥"

temp_dir=""
port=""
password=""
method=""
asset=""
expected_sha256=""
download_prefix=""

info() {
    printf '[信息] %s: %s\n' "${LOG_TAG}" "$*"
}

warn() {
    printf '[警告] %s: %s\n' "${LOG_TAG}" "$*" >&2
}

fail() {
    printf '[错误] %s: %s\n' "${LOG_TAG}" "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${temp_dir}" && "${temp_dir}" == /tmp/shadowsocks-rust.* ]]; then
        rm -rf -- "${temp_dir}"
    fi
}

trap cleanup EXIT

require_root() {
    [[ "${EUID}" -eq 0 ]] || fail '请使用 root 运行此脚本。'
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            asset="shadowsocks-${VERSION}.x86_64-unknown-linux-musl.tar.xz"
            expected_sha256="8439bf43c324b0fc273e663d0b1f8926fd8f666cbd1e0fd59b35096f0e778e92"
            ;;
        aarch64|arm64)
            asset="shadowsocks-${VERSION}.aarch64-unknown-linux-musl.tar.xz"
            expected_sha256="2c24915b56a05effdab5898848bacfbcb625bc277b18febafc7a3aa45f87f3b0"
            ;;
        armv7l|armv7)
            asset="shadowsocks-${VERSION}.armv7-unknown-linux-musleabihf.tar.xz"
            expected_sha256="12cd87a248c6d19ea2a0a4a8d7189ca9198a960fd1eeed027826e06ba2bb81d8"
            ;;
        *)
            fail "暂不支持 CPU 架构 $(uname -m)。"
            ;;
    esac
}

install_dependencies() {
    if command_exists apt-get; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl xz-utils jq
    elif command_exists dnf; then
        dnf install -y ca-certificates curl xz jq
    elif command_exists yum; then
        yum install -y ca-certificates curl xz jq
    else
        fail '找不到 apt-get、dnf 或 yum。'
    fi
    command_exists systemctl || fail '当前系统不支持 systemd。'
}

generate_password() {
    if command_exists openssl; then
        openssl rand -hex 24
    else
        od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
    fi
}

read_settings() {
    local default_port input pick
    if command_exists shuf; then
        default_port="$(shuf -i 9000-19999 -n 1)"
    else
        default_port="13187"
    fi

    printf '请输入 Shadowsocks 密码（直接回车自动生成）：'
    read -r -s password
    printf '\n'
    [[ -n "${password}" ]] || password="$(generate_password)"

    while true; do
        printf '请输入端口 [1-65535]（默认 %s）：' "${default_port}"
        read -r input
        port="${input:-${default_port}}"
        if [[ "${port}" =~ ^[1-9][0-9]*$ ]] && ((10#${port} <= 65535)); then
            break
        fi
        warn '端口格式不正确。'
    done

    printf '\n请选择加密方式：\n'
    printf '1) aes-256-gcm\n2) aes-128-gcm\n3) chacha20-ietf-poly1305\n'
    while true; do
        printf '请选择（默认 1）：'
        read -r pick
        case "${pick:-1}" in
            1) method='aes-256-gcm'; break ;;
            2) method='aes-128-gcm'; break ;;
            3) method='chacha20-ietf-poly1305'; break ;;
            *) warn '请输入 1、2 或 3。' ;;
        esac
    done
}

download_binary() {
    local url prefix actual_sha256
    temp_dir="$(mktemp -d /tmp/shadowsocks-rust.XXXXXX)"
    select_download_prefix
    prefix="${download_prefix}"
    url="${prefix}${BASE_URL}/${asset}"

    info "下载 ${asset}。"
    curl --fail --location --retry 3 --connect-timeout 15 \
        --proto '=https' --tlsv1.2 --output "${temp_dir}/${asset}" "${url}"
    actual_sha256="$(sha256sum "${temp_dir}/${asset}" | awk '{print $1}')"
    [[ "${actual_sha256}" == "${expected_sha256}" ]] || fail 'SHA-256 校验失败。'

    tar -xJf "${temp_dir}/${asset}" -C "${temp_dir}"
    [[ -f "${temp_dir}/ssserver" ]] || fail '发行包中找不到 ssserver。'
    install -o root -g root -m 0755 "${temp_dir}/ssserver" "${BIN_FILE}"
}

select_download_prefix() {
    local direct_url proxy_url direct_code proxy_code
    if [[ -n "${DOWNLOAD_PREFIX:-}" ]]; then
        download_prefix="${DOWNLOAD_PREFIX%/}/"
        info "使用手动指定的下载前缀。"
        return 0
    fi

    direct_url="${BASE_URL}/${asset}"
    direct_code="$(curl --head --location --silent --show-error --max-time 8 \
        --proto '=https' --tlsv1.2 --output /dev/null --write-out '%{http_code}' \
        "${direct_url}" || true)"
    if [[ "${direct_code}" =~ ^2[0-9][0-9]$ || "${direct_code}" =~ ^3[0-9][0-9]$ ]]; then
        info '检测到 GitHub 直连可用，使用直连下载。'
        download_prefix=""
        return 0
    fi

    proxy_url="https://gh-proxy.org/${direct_url}"
    proxy_code="$(curl --head --location --silent --show-error --max-time 8 \
        --proto '=https' --tlsv1.2 --output /dev/null --write-out '%{http_code}' \
        "${proxy_url}" || true)"
    if [[ "${proxy_code}" =~ ^2[0-9][0-9]$ || "${proxy_code}" =~ ^3[0-9][0-9]$ ]]; then
        info 'GitHub 直连不可用，已自动切换 gh-proxy.org。'
        download_prefix='https://gh-proxy.org/'
        return 0
    fi

    fail 'GitHub 直连和 gh-proxy.org 均不可用；可设置 DOWNLOAD_PREFIX 使用其他镜像。'
}

create_service_user() {
    if ! id "${SERVICE_USER}" >/dev/null 2>&1; then
        useradd --system --user-group --no-create-home --shell /usr/sbin/nologin "${SERVICE_USER}"
    fi
}

stop_old_service() {
    systemctl disable --now shadowsocks.service >/dev/null 2>&1 || true
    if [[ -x /etc/init.d/shadowsocks ]]; then
        /etc/init.d/shadowsocks stop >/dev/null 2>&1 || true
    fi
}

write_config() {
    local temp_config
    mkdir -p "${CONFIG_DIR}"
    if [[ -f "${CONFIG_FILE}" ]]; then
        cp -a "${CONFIG_FILE}" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    temp_config="$(mktemp "${CONFIG_DIR}/config.json.XXXXXX")"
    jq -n --arg password "${password}" --arg method "${method}" --argjson port "${port}" \
        '{server:"0.0.0.0",server_port:$port,password:$password,method:$method,mode:"tcp_and_udp",timeout:300}' \
        > "${temp_config}"
    chown root:"${SERVICE_USER}" "${temp_config}"
    chmod 0640 "${temp_config}"
    mv -f "${temp_config}" "${CONFIG_FILE}"
    chown root:"${SERVICE_USER}" "${CONFIG_DIR}"
    chmod 0750 "${CONFIG_DIR}"
}

write_service() {
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Shadowsocks-Rust Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
ExecStart=${BIN_FILE} -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
}

open_firewall() {
    if command_exists ufw && ufw status | grep -q '^Status: active'; then
        ufw allow "${port}/tcp" >/dev/null
        ufw allow "${port}/udp" >/dev/null
        info "UFW 已放行 ${port}/tcp 和 ${port}/udp。"
    elif command_exists firewall-cmd && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null
        firewall-cmd --permanent --add-port="${port}/udp" >/dev/null
        firewall-cmd --reload >/dev/null
        info "firewalld 已放行 ${port}/tcp 和 ${port}/udp。"
    else
        warn "请在云安全组中放行 ${port}/tcp 和 ${port}/udp。"
    fi
}

start_service() {
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}" >/dev/null
    systemctl restart "${SERVICE_NAME}"
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        systemctl --no-pager --full status "${SERVICE_NAME}" || true
        fail '服务启动失败。'
    fi
}

show_result() {
    local server_ip
    server_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    printf '\n安装完成。\n'
    printf '服务器地址：%s\n' "${server_ip:-请查看服务器公网 IP}"
    printf '服务器端口：%s\n' "${port}"
    printf '加密方式：%s\n' "${method}"
    printf '配置文件：%s\n' "${CONFIG_FILE}"
    printf '密码：%s\n' "${password}" > /dev/tty 2>/dev/null || true
}

install_shadowsocks() {
    require_root
    detect_arch
    read_settings
    install_dependencies
    stop_old_service
    create_service_user
    download_binary
    write_config
    write_service
    open_firewall
    start_service
    show_result
}

uninstall_shadowsocks() {
    local answer old_port=""
    require_root
    printf '确认卸载 Shadowsocks-Rust？(y/n，默认 n)：'
    read -r answer
    [[ "${answer:-n}" =~ ^[yY]$ ]] || { info '已取消卸载。'; return; }

    if [[ -f "${CONFIG_FILE}" ]] && command_exists jq; then
        old_port="$(jq -r '.server_port // empty' "${CONFIG_FILE}")"
    fi
    systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
    rm -f "${SERVICE_FILE}" "${BIN_FILE}"
    rm -rf "${CONFIG_DIR}"
    userdel "${SERVICE_USER}" >/dev/null 2>&1 || true
    groupdel "${SERVICE_USER}" >/dev/null 2>&1 || true
    systemctl daemon-reload
    [[ -z "${old_port}" ]] || warn "如不再使用端口 ${old_port}，请从防火墙和云安全组中删除对应 TCP/UDP 规则。"
    info '卸载完成。'
}

show_status() {
    require_root
    systemctl --no-pager --full status "${SERVICE_NAME}"
}

show_help() {
    printf '%s\n' \
        '用法：' \
        '  sudo bash shadowsocks-rust.sh install' \
        '  sudo bash shadowsocks-rust.sh status' \
        '  sudo bash shadowsocks-rust.sh uninstall'
}

case "${1:-install}" in
    install) install_shadowsocks ;;
    status) show_status ;;
    uninstall) uninstall_shadowsocks ;;
    help|-h|--help) show_help ;;
    *) show_help; exit 1 ;;
esac
