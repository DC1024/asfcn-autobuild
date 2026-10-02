# asfcn-autobuild — ArchiSteamFarm + Caddy(Steam 反代) 多架构镜像
# 特色：基础镜像每次构建都取官方最新稳定版，且由 GitHub Actions 定时自动重建 → 上游一发新版就跟上。
FROM ghcr.io/justarchinet/archisteamfarm:latest

LABEL org.opencontainers.image.title="asfcn-autobuild" \
      org.opencontainers.image.description="ArchiSteamFarm + Caddy Steam-community reverse proxy for CN networks; multi-arch (amd64/arm64), automatically rebuilt on every upstream ASF stable release via GitHub Actions" \
      org.opencontainers.image.source="https://github.com/DC1024/asfcn-autobuild" \
      org.opencontainers.image.licenses="Apache-2.0"

ENV ASF_USER=asf
ENV ASPNETCORE_URLS=
ENV DOTNET_CLI_TELEMETRY_OPTOUT=true
ENV DOTNET_NOLOGO=true

# 安装 Caddy（沿用上游 ASFcn 的 testing 源，避免某些源的 2.6.x 证书生成 bug）
RUN apt update && apt install -y curl debian-keyring debian-archive-keyring apt-transport-https libnss3-tools \
 && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/testing/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-testing-archive-keyring.gpg \
 && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/testing/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-testing.list \
 && apt update && apt install -y caddy \
 && rm -rf /var/lib/apt/lists/*

EXPOSE 1242 443

WORKDIR /app
COPY Caddyfile /app/
COPY entrypoint.sh /app/

HEALTHCHECK CMD ["pidof", "-q", "ArchiSteamFarm"]
ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh"]
