# asfcn-autobuild

**ArchiSteamFarm + Caddy（Steam 社区反代）多架构 Docker 镜像 —— 上游一发新版，它自己就重建。**

[![build](https://github.com/DC1024/asfcn-autobuild/actions/workflows/docker.yml/badge.svg)](https://github.com/DC1024/asfcn-autobuild/actions/workflows/docker.yml)
[![ghcr](https://img.shields.io/badge/ghcr.io-dc1024%2Fasfcn--autobuild-2496ed)](https://ghcr.io/dc1024/asfcn-autobuild)

**介绍页：<https://dc1024.github.io/asfcn-autobuild/>** —— 源码在 [`site/`](site/)，**改完 push 即自动发布**到 `gh-pages` 分支（见 `.github/workflows/pages.yml`）。`site/` 目录本身就是网站根目录。

名字里的 **autobuild** 就是本项目的核心：**不依赖容器内自更新，改由 CI 定时自动重建镜像。**
衍生自 [`sffxzzp/ASFcn`](https://github.com/sffxzzp/ASFcn)，专治其「长时间不更新」的问题。

## 一眼看完

| 项目 | 值 |
|---|---|
| 镜像 | `ghcr.io/dc1024/asfcn-autobuild:latest` |
| 钉版本 | `ghcr.io/dc1024/asfcn-autobuild:<ASF版本>`，例如 `:6.3.10.3` |
| 架构 | `linux/amd64` + `linux/arm64`（同一地址，设备自适应） |
| 基础镜像 | `ghcr.io/justarchinet/archisteamfarm:latest`（每次构建即取官方最新稳定版） |
| 跟随通道 | 上游 ASF **稳定版**（不含预发布） |
| 更新方式 | 设备侧只需 `docker compose pull && up -d` |

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

1. **移除 `github.com` 反代**：上游 `entrypoint.sh` 把 `github.com` 指向本地 Caddy，再由 Caddyfile 用**硬编码 GitHub IP** 反代 —— 这些 IP 会失效（实测上游返回 502），导致 ASF 自更新/插件更新**永远失败**。本镜像靠**重建镜像**跟随版本，不再需要容器内自更新，故整段移除。
2. **保留并修复 Steam 反代**：`(rev)` 段加入 `header_up Host {host}`，修复 Akamai 返回 400 导致 bot 反复断连。
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

默认 IPC 密码：`asfcnasfcn`（改 `config/IPC.config`）。

## ⚠️ 网络注意

`ghcr.io` 位于海外。在无稳定出海网络的环境里，设备侧 `docker pull ghcr.io/...` 可能失败。可选：

- 给设备配可用的 HTTP 代理后拉取；或
- 在 CI 中**额外推送一份到阿里云 ACR**（国内可拉），设备改用 ACR 地址。

## 致谢

- [JustArchiNET/ArchiSteamFarm](https://github.com/JustArchiNET/ArchiSteamFarm)（Apache-2.0）
- [sffxzzp/ASFcn](https://github.com/sffxzzp/ASFcn)（本镜像的衍生来源）
- [Caddy](https://caddyserver.com/)
