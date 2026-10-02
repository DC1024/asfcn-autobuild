# asfcn (self-maintained)

**ArchiSteamFarm + Caddy（Steam 社区反代）多架构 Docker 镜像，由 GitHub Actions 自动跟随上游 ASF 发布重建。**

Fork/衍生自 [`sffxzzp/ASFcn`](https://github.com/sffxzzp/ASFcn)（Apache-2.0 生态，ASF 本体为 Apache-2.0）。
本仓库解决原项目「长时间不更新」的问题：**定时轮询上游 ASF 稳定版 + 版本守卫 + 多架构构建 + 自动推送 ghcr**。

- 基础镜像：`ghcr.io/justarchinet/archisteamfarm:latest`（每次构建自动取官方最新稳定版）
- 架构：`linux/amd64`、`linux/arm64`（同一镜像地址，多设备自适应）
- 镜像：`ghcr.io/dc1024/asfcn:latest` / `ghcr.io/dc1024/asfcn:<ASF版本>`

## 相对上游的改动

1. **移除 `github.com` 反代**：上游 `entrypoint.sh` 把 `github.com` 指向本地 Caddy，由 Caddyfile 用**硬编码 GitHub IP** 反代；这些 IP 会失效（实测 Caddy 上游返回 502），导致 ASF 自更新/插件更新永远失败。本镜像靠**重建镜像**跟随版本，不再需要容器内自更新，故移除。
2. **保留并修复 Steam 反代**：`(rev)` 段加入 `header_up Host {host}`，修复 Akamai 返回 400 导致的 bot 反复断连。
3. **CI 改造**：加入 `schedule`（每 2 小时轮询 + 版本守卫）、多架构构建、仅推 ghcr。

## 自动更新机制

```
每 2 小时：
  取上游 ASF 稳定版 tag  →  与本仓库 git tag `asf-<ver>` 比对
    相同 → 跳过（不构建，省 Actions 额度）
    不同 → 构建 amd64+arm64 并推送 ghcr，成功后打 tag asf-<ver>
```
- 滞后上界 = 轮询间隔（≤2h），对**月更的稳定版**等于「发布即跟进」。
- 用 git tag 守卫还能规避 GitHub「仓库 60 天无活动自动停用 schedule」。

## 使用

```yaml
services:
  asf:
    image: ghcr.io/dc1024/asfcn:latest
    container_name: asf
    shm_size: 256mb
    ports:
      - 1242:1242
      - 443:443
    volumes:
      - ./config:/app/config
      - ./logs:/app/logs
      - ./plugins:/app/plugins      # 放第三方插件（如 ASFEnhance）
      # - ./Caddyfile:/app/Caddyfile  # 可选：如需覆盖内置 Caddyfile
      # ⚠️ 不要挂载 /asf ！否则宿主旧程序会盖住镜像里的新程序，导致拉新镜像也不更新
    restart: unless-stopped
```

升级（所有设备同一条命令）：
```bash
docker compose pull && docker compose up -d
```

默认 IPC 密码：`asfcnasfcn`（改 `config/IPC.config`）。

## ⚠️ 网络注意（重要）

`ghcr.io` 位于海外。在**无稳定出海网络**的环境里，设备侧 `docker pull ghcr.io/...` 可能失败。
若设备拉不动，可选方案：
- 设备配置可用的 HTTP 代理后拉取；或
- 在 CI 中**额外推送一份到阿里云 ACR**（国内设备可拉），设备改用 ACR 地址。

## 致谢

- [JustArchiNET/ArchiSteamFarm](https://github.com/JustArchiNET/ArchiSteamFarm)（Apache-2.0）
- [sffxzzp/ASFcn](https://github.com/sffxzzp/ASFcn)（本镜像的衍生来源）
- [Caddy](https://caddyserver.com/)
