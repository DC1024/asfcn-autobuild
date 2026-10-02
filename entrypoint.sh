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

# ---------------------------------------------------------------------------
# 启动自检：把「最容易踩、而且踩了不报错只会安静出事」的三件事直接喊出来。
# 只打日志，不改变任何启动行为。
# ---------------------------------------------------------------------------
warn() { printf '\033[1;33m[asfcn-autobuild][WARN] %s\033[0m\n' "$1" >&2; }

# 1) 生效的 Caddyfile 必须带 header_up Host，否则 Akamai 会返回 400，bot 反复 Disconnected
if ! grep -qE '^[[:space:]]*header_up[[:space:]]+Host([[:space:]]|$)' /app/Caddyfile 2>/dev/null; then
    warn "生效的 /app/Caddyfile 里没有 header_up Host —— Steam 反代会被 Akamai 判 400，bot 会反复 Disconnected。"
    warn "如果你挂载了自定义 Caddyfile，请确认它包含这一行；用不到自定义就直接删掉该挂载，改用镜像内置版本。"
fi

# 2) 上游那段硬编码 IP 的 github.com 反代已失效（会 502），本镜像不再需要
#    只看非注释行，避免把镜像自带 Caddyfile 注释里提到的 github.com 误判
if grep -vE '^[[:space:]]*#' /app/Caddyfile 2>/dev/null | grep -qE 'github'; then
    warn "生效的 /app/Caddyfile 里有 github 反代 —— 上游旧版那段用的是已失效的硬编码 IP（会 502），本镜像靠重建镜像跟版本、不需要它，建议移除。"
    warn "如果你挂载了旧教程里的 Caddyfile，换成镜像内置版本（删掉挂载）即可。"
fi

# 3) IPC 密码还是镜像默认值（ASF 真正读的是 config/ASF.json 里的 IPCPassword）
if grep -qE '"IPCPassword"[[:space:]]*:[[:space:]]*"asfcnasfcn"' /app/config/ASF.json 2>/dev/null; then
    warn "IPC 密码仍是镜像默认值 asfcnasfcn（所有使用者共用）—— 请改掉 config/ASF.json 里的 IPCPassword。"
    if grep -qE '"IPCPassword"' /app/config/IPC.config 2>/dev/null; then
        warn "另外检测到 config/IPC.config 里也写了 IPCPassword —— 那个文件是 Kestrel 侧配置，ASF 不会读它，改在那边不生效。"
    fi
fi

caddy start --config /app/Caddyfile
exec bash /asf/ArchiSteamFarm-Service.sh --no-restart --system-required
