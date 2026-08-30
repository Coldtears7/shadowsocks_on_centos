# Shadowsocks-Rust

安装：

```bash
chmod +x shadowsocks-rust.sh
sudo bash shadowsocks-rust.sh install
```

国内服务器如果直连 GitHub 较慢：

```bash
export DOWNLOAD_PREFIX=https://gh-proxy.org/
sudo -E bash shadowsocks-rust.sh install
```

脚本默认会先自动测试 GitHub 直连，失败后自动切换到 `gh-proxy.org`。只有两个地址都不可用时，才需要手动设置 `DOWNLOAD_PREFIX`。

管理：

```bash
sudo bash shadowsocks-rust.sh status
sudo systemctl restart shadowsocks-rust
sudo journalctl -u shadowsocks-rust -n 50 --no-pager
sudo bash shadowsocks-rust.sh uninstall
```

配置文件：`/etc/shadowsocks-rust/config.json`

默认加密方式为 `aes-256-gcm`，默认端口随机生成。云安全组需要放行所选端口的 TCP 和 UDP。
