# syntax=docker/dockerfile:1
#
# opencode v2 — container image based on the official prebuilt binary,
# designed to run `opencode serve` (API + web UI) out of the box.
#
# The binary is the one published on npm as @opencode/cli-linux-<arch>
# (same source used by the official script https://opencode.ai/v2/install).
# The version is resolved at build time:
#   - if OPENCODE_VERSION is a number (e.g. 2.0.29) it uses it
#   - if it is "latest" / "v2" / "2" / empty it resolves the newest 2.x from the npm registry
#
# Default command is `serve --hostname 0.0.0.0 --port 4096` so the web UI
# is reachable from outside the container (upstream defaults to 127.0.0.1).
# Set OPENCODE_SERVER_PASSWORD to protect it, otherwise a random password
# is generated on every start (see container logs).
#
# Local build:
#   docker build --build-arg OPENCODE_VERSION=2.0.29 -t myuser/opencode-v2:2.0.29 .
#   docker build --build-arg OPENCODE_VERSION=latest -t myuser/opencode-v2:test .
#
# Multi-arch (requires buildx):
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     --build-arg OPENCODE_VERSION=latest -t myuser/opencode-v2:latest .

ARG DEBIAN_VERSION=bookworm-slim
FROM debian:${DEBIAN_VERSION}

ARG OPENCODE_VERSION=latest
ARG TARGETARCH

# Image metadata. Defaults describe this project; override at build time
# (the pipeline passes them automatically, so forks need no Dockerfile edit).
ARG IMAGE_NAME=guarnacciaa/opencode-v2
ARG SOURCE_REPO=https://github.com/guarnacciaa/opencode-v2-containerized

LABEL org.opencontainers.image.title="opencode v2" \
      org.opencontainers.image.description="Container image for opencode v2 (binary from npm @opencode/cli-linux-*)" \
      org.opencontainers.image.source="${SOURCE_REPO}" \
      org.opencontainers.image.url="https://hub.docker.com/r/${IMAGE_NAME}" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    OPENCODE_CONFIG_DIR=/home/opencode/.config/opencode \
    OPENCODE_HOSTNAME=0.0.0.0 \
    OPENCODE_PORT=4096

# Documentary only: the actual port comes from OPENCODE_PORT / --port at runtime.
EXPOSE 4096

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
      tar \
      git \
      openssh-client \
      ripgrep; \
    rm -rf /var/lib/apt/lists/*; \
    \
    # TARGETARCH (buildx) is amd64/arm64, npm uses x64/arm64 \
    arch="${TARGETARCH:-amd64}"; \
    case "$arch" in \
      amd64) npm_arch="x64" ;; \
      arm64) npm_arch="arm64" ;; \
      *) echo "Unsupported TARGETARCH: $arch" >&2; exit 1 ;; \
    esac; \
    \
    # Version resolution: latest/v2/2/empty -> newest 2.x on npm \
    version="${OPENCODE_VERSION}"; \
    case "$version" in \
      ""|"latest"|"v2"|"v2-latest"|"2") \
        echo "Resolving latest opencode v2 from npm registry..."; \
        version="$(curl -fsSL "https://registry.npmjs.org/@opencode%2fcli-linux-x64" \
          | jq -r '.versions | keys[] | select(startswith("2."))' \
          | sort -V | tail -n 1)"; \
        ;; \
      v*) version="${version#v}" ;; \
    esac; \
    if [ -z "$version" ]; then echo "Unable to resolve opencode version" >&2; exit 1; fi; \
    echo "Installing opencode v${version} for linux-${npm_arch}"; \
    \
    # Current npm scope: @opencode, legacy fallback @opencode-ai for old 2.x \
    pkg_scope="@opencode"; \
    tgz="https://registry.npmjs.org/${pkg_scope}/cli-linux-${npm_arch}/-/cli-linux-${npm_arch}-${version}.tgz"; \
    if ! curl -fsSL -o /tmp/opencode.tgz "$tgz"; then \
      echo "Falling back to legacy scope @opencode-ai..."; \
      pkg_scope="@opencode-ai"; \
      tgz="https://registry.npmjs.org/${pkg_scope}/cli-linux-${npm_arch}/-/cli-linux-${npm_arch}-${version}.tgz"; \
      curl -fsSL -o /tmp/opencode.tgz "$tgz"; \
    fi; \
    mkdir -p /tmp/opencode-pkg; \
    tar -xzf /tmp/opencode.tgz -C /tmp/opencode-pkg; \
    ls -la /tmp/opencode-pkg/package/bin/; \
    mv "/tmp/opencode-pkg/package/bin/opencode" /usr/local/bin/opencode; \
    chmod 755 /usr/local/bin/opencode; \
    # compat: the official install script also provides the opencode2 shim \
    ln -sf /usr/local/bin/opencode /usr/local/bin/opencode2; \
    rm -rf /tmp/opencode.tgz /tmp/opencode-pkg; \
    \
    # non-root user + smoke test \
    useradd -m -s /bin/bash opencode; \
    mkdir -p /workspace /home/opencode/.config/opencode; \
    chown -R opencode:opencode /workspace /home/opencode; \
    opencode --version; \
    echo "$version" > /opencode-version.txt; \
    cat /opencode-version.txt

WORKDIR /workspace

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER opencode

# TCP check on purpose: HTTP paths require auth, but an accepted
# connection proves the server is listening. Honors OPENCODE_PORT.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/${OPENCODE_PORT:-4096}'

ENTRYPOINT ["docker-entrypoint.sh"]
# No args: the entrypoint expands this to
# serve --hostname $OPENCODE_HOSTNAME --port $OPENCODE_PORT
CMD ["serve"]
