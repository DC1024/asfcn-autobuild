#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# asfcn-autobuild 一键自检
#
#   在装了 docker 的宿主机上、于 compose 文件所在目录执行：
#       bash verify.sh
#
# 可选环境变量（不设也能跑，会自动探测）：
#   CONTAINER=asf        容器名
#   DOCKER="sudo docker" 需要 sudo 的机器上这样写
#   HTTPS_PORT=443       容器发布到宿主机的 Caddy 端口
#   IPC_PORT=1242        ASF-ui / IPC 端口
#   IPC_PASS=xxx         IPC 密码（不填则从容器内 config/ASF.json 读取）
#
# 退出码：0 = 没有 FAIL；1 = 存在 FAIL
# ---------------------------------------------------------------------------
set -uo pipefail

CT="${CONTAINER:-asf}"
DK="${DOCKER:-docker}"
HTTPS_PORT="${HTTPS_PORT:-443}"
IPC_PORT="${IPC_PORT:-1242}"
IPC_PASS="${IPC_PASS:-}"
HTTP_HOST="${HTTP_HOST:-127.0.0.1}"

PASS=0; FAIL=0; SKIP=0
if [ -t 1 ]; then
    G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
    G=""; R=""; Y=""; B=""; N=""
fi

ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  %s·%s %s\n' "$Y" "$N" "$1"; SKIP=$((SKIP + 1)); }
wt()   { printf '  %s!%s %s\n' "$Y" "$N" "$1"; }
hd()   { printf '\n%s%s%s\n' "$B" "$1" "$N"; }
die()  { printf '%s%s%s\n' "$R" "$1" "$N" >&2; exit 1; }

# shellcheck disable=SC2086  # DK 可能含空格（"sudo docker"），故意不加引号
cinspect() { $DK inspect -f "$1" "$CT" 2>/dev/null; }

command -v ${DK%% *} >/dev/null 2>&1 || die "找不到 ${DK%% *}，请先安装 docker，或用 DOCKER=\"sudo docker\" 重试。"

if ! cinspect '{{.Id}}' >/dev/null 2>&1 || [ -z "$(cinspect '{{.Id}}')" ]; then
    die "找不到容器 ${CT}。用 CONTAINER=<容器名> 指定，或先确认它已启动。"
fi

printf '%sasfcn-autobuild 自检%s   容器=%s\n' "$B" "$N" "$CT"

# ---------------------------------------------------------------- 1. 运行状态
hd "1/9  容器运行状态"
STATUS="$(cinspect '{{.State.Status}}')"
HEALTH="$(cinspect '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}')"
RESTARTS="$(cinspect '{{.RestartCount}}')"
if [ "$STATUS" = "running" ]; then
    if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "-" ]; then
        ok "running / health=${HEALTH}（重启次数 ${RESTARTS}）"
    else
        bad "容器在跑但 health=${HEALTH}（重启次数 ${RESTARTS}）—— 看 docker logs ${CT}"
    fi
else
    bad "容器状态是 ${STATUS}，不是 running"
fi

# ---------------------------------------------------------------- 2. 镜像正确
hd "2/9  镜像与 ASF 版本"
IMAGE="$(cinspect '{{.Config.Image}}')"
if printf '%s' "$IMAGE" | grep -q 'asfcn-autobuild'; then
    ok "镜像 = ${IMAGE}"
else
    bad "镜像 = ${IMAGE} —— 期望含 asfcn-autobuild；旧路径 ghcr.io/dc1024/asfcn 已失效，请改成新地址"
fi
BOOTSTART="$(cinspect '{{.State.StartedAt}}' | sed 's/\.[0-9]*Z$/Z/')"
if [ -n "$BOOTSTART" ]; then
    BOOTLOG="$($DK logs --since "$BOOTSTART" "$CT" 2>&1)"
else
    BOOTLOG="$($DK logs "$CT" 2>&1)"
fi
VER="$(printf '%s\n' "$BOOTLOG" | grep -oE 'ArchiSteamFarm V[0-9.]+' | tail -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')"
if [ -n "$VER" ]; then
    ok "本次启动 ASF 版本 = ${VER}"
else
    wt "日志里没抓到 ASF 版本号（可能启动信息被截断，不影响结论）"
fi

# ---------------------------------------------------------------- 3. 挂载点
hd "3/9  挂载点（绝不能有 /asf）"
DESTS="$(cinspect '{{range .Mounts}}{{.Destination}} {{end}}')"
if printf '%s' "$DESTS" | grep -qw '/asf'; then
    bad "检测到 /asf 挂载 —— 宿主旧程序会盖住镜像里的新程序，症状是「拉了新镜像也不更新」。请删掉这条挂载"
else
    ok "无 /asf 挂载；当前挂载：${DESTS:-（无）}"
fi
for need in /app/config /app/logs; do
    printf '%s' "$DESTS" | grep -qw "$need" || wt "没有挂载 ${need} —— 重启会丢数据，建议补上"
done

# ---------------------------------------------------------------- 4. Caddyfile 健全性
hd "4/9  生效的 Caddyfile 是否健全"
if $DK exec "$CT" sh -c 'test -f /app/Caddyfile' 2>/dev/null; then
    if $DK exec "$CT" sh -c 'grep -qE "^[[:space:]]*header_up[[:space:]]+Host([[:space:]]|$)" /app/Caddyfile' 2>/dev/null; then
        ok "含 header_up Host（Akamai 不会返回 400）"
    else
        bad "缺少 header_up Host —— Steam 反代会被 Akamai 判 400，bot 反复 Disconnected"
    fi
    # 只看非注释行，避免把我们自己注释里提到的 github.com 误判
    GH="$($DK exec "$CT" sh -c "grep -vE '^[[:space:]]*#' /app/Caddyfile | grep -c github" 2>/dev/null | tr -d '\r')"
    if [ "${GH:-0}" -gt 0 ]; then
        bad "生效的 Caddyfile 里还有 github 反代（${GH} 行）—— 上游那段用的是已失效的硬编码 IP（会 502），本镜像靠重建镜像跟版本、不需要它"
        wt "多半是宿主机挂载的 Caddyfile 盖住了镜像内置的干净版本：把它换成仓库里的 Caddyfile，或删掉这条挂载"
    else
        ok "无 github 反代残留"
    fi
else
    bad "容器内没有 /app/Caddyfile（正常镜像一定自带，出现即异常）"
fi

# ---------------------------------------------------------------- 5. 插件不重复
hd "5/9  官方插件是否被重复放置"
PLUG_SRC="$(cinspect '{{range .Mounts}}{{if eq .Destination "/app/plugins"}}{{.Source}}{{end}}{{end}}')"
if [ -n "$PLUG_SRC" ] && [ -d "$PLUG_SRC" ]; then
    DUP="$(ls -1 "$PLUG_SRC" 2>/dev/null | grep -iE '^(ItemsMatcher|MobileAuthenticator|SteamTokenDumper)' || true)"
    if [ -n "$DUP" ]; then
        bad "宿主 plugins 卷里有官方插件副本：$(printf '%s' "$DUP" | tr '\n' ' ')—— 官方插件由镜像提供，删掉这些副本"
    else
        ok "宿主 plugins 卷只含第三方插件（$(ls -1 "$PLUG_SRC" 2>/dev/null | tr '\n' ' '))"
    fi
else
    skip "没有 plugins 挂载，跳过（官方插件由镜像自带，本项无风险）"
fi
DUPERR="$(printf '%s\n' "$BOOTLOG" | grep -c 'Assembly with same name is already loaded' || true)"
if [ "${DUPERR:-0}" -gt 0 ]; then
    bad "本次启动有 ${DUPERR} 行「Assembly with same name is already loaded」= 插件重复加载"
else
    ok "本次启动无插件重复加载报错"
fi

# ---------------------------------------------------------------- 5. 启动零 ERROR
hd "6/9  本次启动的 ERROR 数（按 boot 分口径）"
ERRN="$(printf '%s\n' "$BOOTLOG" | grep -c 'ERROR' || true)"
if [ "${ERRN:-0}" -eq 0 ]; then
    ok "本次启动 ERROR = 0"
else
    bad "本次启动 ERROR = ${ERRN}；前几行样例："
    printf '%s\n' "$BOOTLOG" | grep 'ERROR' | head -n3 | sed 's/^/      /'
fi
if printf '%s\n' "$BOOTLOG" | grep -q 'physicalPath .* is invalid'; then
    wt "出现 ConfigureApp() physicalPath ... is invalid! —— 这条对 ASFEnhance 属正常告警，勿改 Plugins.ASFEnhance.PhysicalPath"
fi

# ---------------------------------------------------------------- 6. bot 登录
hd "7/9  bot 登录与挂卡"
if printf '%s\n' "$BOOTLOG" | grep -q 'Successfully logged on as'; then
    LOGGED="$(printf '%s\n' "$BOOTLOG" | grep -o 'Successfully logged on as [^ ]*' | head -n1)"
    ok "$LOGGED"
else
    bad "本次启动没看到 'Successfully logged on as' —— 检查 config/*.json 里的账号与 Enabled"
fi
if printf '%s\n' "$BOOTLOG" | grep -qE 'StartFarming\(\)|Now farming'; then
    ok "已进入挂卡状态（StartFarming / Now farming）"
else
    wt "没看到挂卡开始日志（可能尚未发生，或该 bot 无可挂卡）"
fi

# ---------------------------------------------------------------- 7. 反代连通
hd "8/9  Steam 反代连通（宿主机 → 容器 Caddy → Akamai）"
PUBLISHED="$(cinspect "{{range \$p, \$b := .NetworkSettings.Ports}}{{if eq \$p \"${HTTPS_PORT}/tcp\"}}{{range \$b}}{{.HostPort}}{{end}}{{end}}{{end}}")"
if ! command -v curl >/dev/null 2>&1; then
    skip "宿主机没有 curl，跳过反代连通性检查（可在容器内手工 curl）"
elif [ -z "$PUBLISHED" ]; then
    skip "${HTTPS_PORT}/tcp 没有发布到宿主机，跳过（改 HTTPS_PORT=<已发布端口> 可启用）"
else
    check_url() { # $1=域名 $2=期望码
        CODE="$(curl -k -s -o /dev/null -w '%{http_code}' -m 20 \
                --resolve "$1:${HTTPS_PORT}:${HTTP_HOST}" "https://$1:${HTTPS_PORT}/" 2>/dev/null)"
        if [ "$CODE" = "$2" ]; then
            ok "$1 → $CODE"
        else
            bad "$1 → ${CODE:-连接失败}（期望 $2）"
        fi
    }
    check_url steamcommunity.com 200
    check_url store.steampowered.com 200
    check_url api.steampowered.com 404
fi

# ---------------------------------------------------------------- 8. IPC
hd "9/9  ASF IPC 接口"
if [ -z "$IPC_PASS" ]; then
    IPC_PASS="$($DK exec "$CT" sh -c 'sed -n "s/.*\"IPCPassword\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" /app/config/ASF.json 2>/dev/null | head -n1' 2>/dev/null | tr -d '\r')"
fi
if [ -z "$IPC_PASS" ]; then
    skip "读不到 IPC 密码，跳过（可 IPC_PASS=xxx bash verify.sh）"
elif ! command -v curl >/dev/null 2>&1; then
    skip "宿主机没有 curl，跳过"
else
    if [ "$IPC_PASS" = "asfcnasfcn" ]; then
        wt "IPC 密码仍是镜像默认值 asfcnasfcn，建议改掉 config/ASF.json 里的 IPCPassword"
    fi
    IPC_URL="http://${HTTP_HOST}:${IPC_PORT}/Api/ASF"
    ipc_ok() { printf '%s' "$1" | grep -q '"Result"' && ! printf '%s' "$1" | grep -q '"Success":false'; }
    # 注意：ASF IPC 用的是 Authentication 请求头（值 = IPCPassword），HTTP Basic 会返回 401
    BODY="$(curl -s -m 10 -H "Authentication: ${IPC_PASS}" "$IPC_URL" 2>/dev/null)"
    if ipc_ok "$BODY"; then
        ok "IPC /Api/ASF 鉴权通过（Authentication 头）"
    else
        BODY_basic="$(curl -s -m 10 -u "ASF:${IPC_PASS}" "$IPC_URL" 2>/dev/null)"
        if ipc_ok "$BODY_basic"; then
            ok "IPC /Api/ASF 鉴权通过（HTTP Basic 回退）"
        elif [ -n "$BODY" ]; then
            bad "IPC 有响应但鉴权失败（前 120 字符）：$(printf '%s' "$BODY" | head -c 120)"
            wt "密码取自 config/ASF.json 的 IPCPassword；确认 ${IPC_PORT} 已发布到宿主机"
        else
            bad "IPC 无响应 —— 确认 ${IPC_PORT} 已发布到宿主机、容器在跑"
        fi
    fi
fi

# ---------------------------------------------------------------- 汇总
printf '\n%s结果：%sPASS=%d  FAIL=%d  SKIP=%d\n' "$B" "$N" "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
    printf '%s有 %d 项未通过，逐条看上面的 ✗。%s\n' "$R" "$FAIL" "$N"
    exit 1
fi
printf '%s全部通过。%s\n' "$G" "$N"
