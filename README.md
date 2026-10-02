# asfcn-autobuild

**ArchiSteamFarm + Caddy（Steam 社区反代）多架构 Docker 镜像 —— 上游一发新版，它自己就重建。**

[![build](https://github.com/DC1024/asfcn-autobuild/actions/workflows/docker.yml/badge.svg)](https://github.com/DC1024/asfcn-autobuild/actions/workflows/docker.yml)
[![ghcr](https://img.shields.io/badge/ghcr.io-dc1024%2Fasfcn--autobuild-2496ed)](https://ghcr.io/dc1024/asfcn-autobuild)

**介绍页：<https://dc1024.github.io/asfcn-autobuild/>** —— 源码在 [`site/`](site/)，**改完 push 即自动发布**到 `gh-pages` 分支（见 `.github/workflows/pages.yml`）。`site/` 目录本身就是网站根目录。

名字里的 **autobuild** 就是本项目的核心：**不依赖容器内自更新，改由 CI 定时自动重建镜像。**
衍生自 [`sffxzzp/ASFcn`](https://github.com/sffxzzp/ASFcn)，沿用它的 Steam 反代思路，把版本更新从容器内搬到了 CI。

## 一眼看完

| 项目 | 值 |
|---|---|
| 镜像 | `ghcr.io/dc1024/asfcn-autobuild:latest` |
| 钉版本 | `ghcr.io/dc1024/asfcn-autobuild:<ASF版本>`，例如 `:6.3.10.3` |
| 架构 | `linux/amd64` + `linux/arm64`（同一地址，设备自适应） |
| 基础镜像 | `ghcr.io/justarchinet/archisteamfarm:latest`（每次构建即取官方最新稳定版） |
| 跟随通道 | 上游 ASF **稳定版**（不含预发布） |
| 更新方式 | 设备侧只需 `docker compose pull && up -d` |
| 自检 | 仓库内 [`verify.sh`](verify.sh)，一条命令跑 9 项检查 |

## 自定义构建怎么转

```
每 2 小时（GitHub Actions schedule）
  ├─ 取上游 ASF 稳定版 tag
  ├─ 与本仓库 git tag asf-<ver> 比对
  │    相同 → 跳过，不浪费构建额度
  │    不同 → 构建 linux/amd64 + linux/arm64，推送 ghcr
  └─ 构建成功 → 打 tag asf-<ver>（兼作「保活」，规避 GitHub 仓库 60 天无活动停用 schedule）
```

- **滞后上界 = 轮询间隔（≤2 小时）**。对月更的稳定版，等于「发布即跟进」。
- `push` 只在构建相关文件变化时触发；也支持手动 `workflow_dispatch`。
- 构建标签带 `latest` 与 `<ASF版本>` 双标签，需要回滚就钉版本号。

## 相对上游 ASFcn 的改动

1. **不依赖容器内自更新**：本镜像靠**重建镜像**跟随版本，因此不需要在容器内维护一条对外的更新链路，`github.com` 反代整段移除，只保留 Steam 反代。
2. **保留 Steam 反代并适配 Akamai**：`(rev)` 段加入 `header_up Host {host}`，满足 Akamai 的 Host 校验，避免 bot 反复断连。
3. **CI 改造**：加 `schedule` 轮询 + 版本守卫 + 多架构 buildx，只推 ghcr；镜像名由仓库名推导，改名无需改流水线。

## 使用

```yaml
services:
  asf:
    image: ghcr.io/dc1024/asfcn-autobuild:latest
    container_name: asf
    shm_size: 256mb
    ports:
      - 1242:1242
      - 443:443
    volumes:
      - ./config:/app/config
      - ./logs:/app/logs
      - ./plugins:/app/plugins      # 第三方插件放这里（如 ASFEnhance）
      # - ./Caddyfile:/app/Caddyfile  # 可选：覆盖内置 Caddyfile
      # ⚠️ 不要挂载 /asf ！否则宿主旧程序会盖住镜像里的新程序，导致「拉了新镜像也不更新」
    restart: unless-stopped
```

升级（所有设备同一条命令）：

```bash
docker compose pull && docker compose up -d
```

> `plugins` 卷里**只放第三方插件**。官方插件（ItemsMatcher / MobileAuthenticator / SteamTokenDumper）镜像内自带，放重复副本会让 ASF 两处都扫、启动刷几百行重复报错。

> ⚠️ **别沿用老教程里的「修复版 Caddyfile」**。老教程挂载的那份除了 Steam 反代，还带着三段 `github.com` / `github.io` / `raw.githubusercontent.com` 反代，本镜像不依赖它（版本走镜像层）。内置的 Caddyfile 已无这些段落 —— 要改反代就改内置那份，或者干脆删掉 `Caddyfile` 挂载。挂载的宿主文件会**完全盖住**镜像内置版本，这也是「镜像明明是最新的、行为却还是旧的」最常见的成因。

默认 IPC 密码 `asfcnasfcn`，**改在 `config/ASF.json` 的 `IPCPassword`**（`IPC.config` 是 Kestrel 侧配置，改那里不生效）。容器启动时会自己体检这三件事：生效的 Caddyfile 缺 `header_up Host`、Caddyfile 里还有 github 反代、IPC 密码仍是默认值 —— 任一命中都会在日志里打 `[asfcn-autobuild][WARN]`。

## 换设备 / 迁移

只搬 `config/` 一个目录就够（`logs/`、`plugins/` 里没有账号状态）。但有个关键点：

- ✅ `bot.json` 和 `bot.db` **必须一起搬** —— `.db` 里存着登录令牌，一起搬过去就不用重新走登录验证。
- ❌ 只搬 `bot.json` 的话，ASF 会重新登录，可能触发 Steam Guard / 邮件令牌，甚至要重新过 2FA。

```bash
# 旧机：停容器，只打包 config
docker compose stop
tar -czf asf-config-$(date +%F).tar.gz -C /path/to/asf config

# 新机：解包后直接起
tar -xzf asf-config-*.tar.gz -C /path/to/asf
docker compose up -d
```

搬完在新机跑一次 `bash verify.sh`（见下节），确认 bot 已登录、反代通、没有重复插件报错。

## 自检：verify.sh

仓库自带 `verify.sh`，在装了 docker 的宿主机、于 compose 文件所在目录执行，一条命令跑完 9 项：

```bash
bash verify.sh
# 需要 sudo 的机器：
DOCKER="sudo docker" bash verify.sh
```

检查内容：容器健康 / 镜像地址是不是新的 / **有没有误挂 `/asf`** / 生效的 Caddyfile 是否健全（缺 `header_up Host`、或还留着 github 反代，都会报）/ 插件有没有重复放置 / 本次启动 ERROR 数 / bot 是否登录并开始挂卡 / Steam 三个域名能否经反代连通 / IPC 接口能否鉴权。

退出码 `0` = 全过，`1` = 有未通过项，方便接进你自己的巡检脚本。可用 `CONTAINER=`、`HTTPS_PORT=`、`IPC_PORT=`、`IPC_PASS=` 覆盖默认值。

> 关于 IPC 鉴权：ASF 用的是 `Authentication` 请求头（值就是 `IPCPassword`），**不是 HTTP Basic** —— 用 `curl -u` 会稳定拿到 401。

## 凭证与隐私

- 镜像**不提供**任何 Steam 账号、密码、bot 名的默认值，100% 由使用者自己填。
- 唯一的默认值是通用 IPC 密码 `asfcnasfcn`，**务必改掉**（改 `config/ASF.json` 的 `IPCPassword`）。
- `bot.json` 里的 `SteamPassword` 是**明文**，只留在服务器本地，不要进 git、不要外发。
- 建议给配置目录收紧权限：`chmod 700 config`。

## 已知局限

- **只反代 Steam 社区 / 商店 / API 这几个域名**，不反代 `github.com`。所以容器内能否访问 GitHub 取决于宿主网络 —— 这正是把版本更新交给「重建镜像 + 宿主 `pull`」的原因，镜像默认 `UpdatePeriod: 0`（关掉容器内自更新）。
- **自签证书**：容器内 Caddy 用内部 CA 签证书，拿浏览器直接访问那几个反代域名的 https 会提示不安全，属正常。
- **`ghcr.io` 在海外**：国内多数线路可直连，但不保证（见下节）。
- **钉版本号可以回滚**，但只能回溯到本仓库已经构建过的 tag。

## ⚠️ 网络注意

`ghcr.io` 位于海外。在无稳定出海网络的环境里，设备侧 `docker pull ghcr.io/...` 可能失败。可选：

- 给设备配可用的 HTTP 代理后拉取；或
- 在 CI 中**额外推送一份到阿里云 ACR**（国内可拉），设备改用 ACR 地址。

## 致谢

- [JustArchiNET/ArchiSteamFarm](https://github.com/JustArchiNET/ArchiSteamFarm)（Apache-2.0）
- [sffxzzp/ASFcn](https://github.com/sffxzzp/ASFcn)（本镜像的衍生来源）
- [Caddy](https://caddyserver.com/)
