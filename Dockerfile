# ==============================================================================
# Final Version
#
# This version uses Alpine's package manager to install sing-box,
# which is simpler and more reliable than downloading from GitHub.
# It completely avoids the "404 Not Found" error.
# ==============================================================================

# 1. Use a modern Alpine base image
FROM alpine:3.20

# 2. Add standardized OCI labels for professionalism
#    (You can customize these values)
LABEL maintainer="YourName <your.email@example.com>" \
      org.opencontainers.image.title="WireGuard + Sing-box HA Proxy" \
      org.opencontainers.image.description="A High-Availability Docker image that connects to CloudFlare WARP and exposes a Sing-box proxy." \
      org.opencontainers.image.url="https://github.com/YourName/YourRepo"

# 3. Define build-time arguments
ARG WARP_VERSION="v2.0.2"
ARG TARGETARCH

# 4. BEST PRACTICE: Install sing-box from the Alpine testing repository
#    This is the most reliable method.
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    set -ex && \
    apk update && \
    apk add --no-cache \
        curl ca-certificates iproute2 iptables \
        wireguard-tools openresolv tar bash net-tools \
        sing-box

# 5. Automatically install the warp tool
RUN set -ex && \
    echo ">>> Building for architecture: ${TARGETARCH}" && \
    echo ">>> Downloading WARP tools version: ${WARP_VERSION}" && \
    curl -fsSL -o /usr/local/bin/warp \
      "https://github.com/P3TERX/warp.sh/releases/download/${WARP_VERSION}/warp-linux-${TARGETARCH}" && \
    chmod +x /usr/local/bin/warp

# 6. Install wgcf
RUN curl -fsSL git.io/wgcf.sh | bash

# 7. Set up the entrypoint and default command
WORKDIR /wgcf
COPY entry.sh /run/entry.sh
RUN chmod +x /run/entry.sh

ENTRYPOINT ["/run/entry.sh"]
CMD ["-4"]
