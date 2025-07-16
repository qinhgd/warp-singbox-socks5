好的，没问题。

这是用于启动您镜像 ghcr.io/qinhgd/singbox-wgcf-proxy:v7.0 的完整 docker run 命令。

这条命令包含了所有必需的权限和网络配置，以确保容器内的 WireGuard 隧道和代理服务能正常工作。

完整启动命令 (IPv4 优先模式)
直接复制并执行即可。

Bash

docker run -d \
  --name singbox-proxy \
  --restart unless-stopped \
  --privileged \
  --cap-add NET_ADMIN \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -v /lib/modules:/lib/modules:ro \
  -p 1080:1080/tcp \
  -p 1080:1080/udp \
  ghcr.io/qinhgd/singbox-wgcf-proxy:v7.0
命令解释
docker run -d: 在后台以“分离模式”运行容器。

--name singbox-proxy: 给您的容器起一个好记的名字，方便管理。

--restart unless-stopped: Docker 会在容器退出或宿主机重启后，自动重新启动这个容器，确保服务持续在线。

--privileged 和 --cap-add NET_ADMIN: 赋予容器高级权限，使其能够修改网络设置，这是运行 WireGuard 等网络工具所必需的。

--sysctl net.ipv6.conf.all.disable_ipv6=0: 在容器内启用 IPv6 协议栈，确保 IPv6 流量可以正常代理。

-v /lib/modules:/lib/modules:ro: 将主机的内核模块目录挂载到容器内（只读模式），以便 WireGuard 能正常工作。

-p 1080:1080/tcp 和 -p 1080:1080/udp: 同时映射 TCP 和 UDP 的 1080 端口。这非常重要，能确保您的代理服务同时支持网页浏览（TCP）和游戏、通话（UDP）等应用。

ghcr.io/qinhgd/singbox-wgcf-proxy:v7.0: 您要运行的镜像。

