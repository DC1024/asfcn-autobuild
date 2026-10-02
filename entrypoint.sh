#!/bin/bash
# ASFcn (self-maintained fork) entrypoint
# 将 Steam 相关域名指向本机 Caddy（127.0.0.1），由 Caddy 反代到 Akamai edge，绕过 SNI 阻断。
# 注意：已移除上游的 github.com -> 127.0.0.1 映射。本镜像靠“重建镜像”跟随 ASF 版本，
#       不再依赖容器内自更新，因此无需 GitHub 反代（上游硬编码的 GitHub IP 已失效，是 502 元凶）。
set -u

echo '127.0.0.1 steamcommunity.com www.steamcommunity.com cdn.steamcommunity.com store.steampowered.com api.steampowered.com' >> /etc/hosts

if [ ! -f "/app/config/IPC.config" ]; then
    echo '{"Kestrel":{"Endpoints":{"HTTP":{"Url":"http://*:1242"}}}}' >> /app/config/IPC.config
fi

if [ ! -f "/app/config/ASF.json" ]; then
    echo '{"IPCPassword":"asfcnasfcn","UpdateChannel": 0,"UpdatePeriod": 0,"Statistics": false}' >> /app/config/ASF.json
fi

caddy start --config /app/Caddyfile
exec bash /asf/ArchiSteamFarm-Service.sh --no-restart --system-required
