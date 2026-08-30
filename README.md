### 一键安装shadowsocks

### 通用
```
export DOWNLOAD_PREFIX=https://gh-proxy.org/
```

```
wget --no-check-certificate -O shadowsocks.sh https://raw.githubusercontent.com/Coldtears7/shadowsocks_on_centos/refs/heads/main/shadowsocks-rust.sh && chmod +x shadowsocks.sh && ./shadowsocks.sh 2>&1 | tee shadowsocks.log
```

#### 国外服务器：
```
wget --no-check-certificate -O shadowsocks.sh https://raw.githubusercontent.com/Coldtears7/shadowsocks_on_centos/refs/heads/main/shadowsocks.sh && chmod +x shadowsocks.sh && ./shadowsocks.sh 2>&1 | tee shadowsocks.log
```
#### 国内服务器：
```
wget --no-check-certificate -O shadowsocks.sh https://gh-proxy.org/https://raw.githubusercontent.com/Coldtears7/shadowsocks_on_centos/refs/heads/main/shadowsocks.sh && chmod +x shadowsocks.sh && ./shadowsocks.sh 2>&1 | tee shadowsocks.log
```

#### 卸载方法
```./shadowsocks.sh uninstall```
#### 配置文件路径
```/etc/shadowsocks.json```
#### 常用命令:
#启动:
```/etc/init.d/shadowsocks start```
#停止:
```/etc/init.d/shadowsocks stop```
#重启:
```/etc/init.d/shadowsocks restart```
#查看状态:
```/etc/init.d/shadowsocks status```
