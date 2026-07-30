FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl git unzip ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY package.zip /workspace/package.zip
COPY smoke.ps1 /workspace/smoke.ps1

CMD ["pwsh", "/workspace/smoke.ps1"]
