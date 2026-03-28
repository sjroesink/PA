# =============================================================================
# Stage 1: Builder
# =============================================================================
FROM ubuntu:22.04 AS builder

ARG HERMES_VERSION=b8b1f24
ARG PYTHON_VERSION=3.11

ENV DEBIAN_FRONTEND=noninteractive

# System build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates build-essential pkg-config libssl-dev \
    software-properties-common gpg-agent \
    && rm -rf /var/lib/apt/lists/*

# Python 3.11 via deadsnakes PPA
RUN add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# uv package manager
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# Clone hermes-agent at pinned version
RUN git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes/app \
    && cd /opt/hermes/app \
    && git checkout ${HERMES_VERSION}

WORKDIR /opt/hermes/app

# Python virtual environment
RUN uv venv /opt/hermes/venv --python /usr/bin/python${PYTHON_VERSION}
ENV VIRTUAL_ENV=/opt/hermes/venv
ENV PATH="/opt/hermes/venv/bin:${PATH}"

# Install all Python dependencies
RUN uv pip install -e ".[all]"

# Install tinker-atropos submodule if present
RUN if [ -f tinker-atropos/pyproject.toml ]; then \
      uv pip install -e ./tinker-atropos; \
    fi

# Node.js dependencies (agent-browser)
RUN npm install


# =============================================================================
# Stage 2: Runtime
# =============================================================================
FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Runtime system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ripgrep ffmpeg curl ca-certificates \
    software-properties-common gpg-agent \
    openssh-server sudo \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd

# Python 3.11 runtime (no dev headers)
RUN add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3.11-distutils \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 runtime
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Copy Python venv and app from builder
COPY --from=builder /opt/hermes /opt/hermes

ENV VIRTUAL_ENV=/opt/hermes/venv
ENV PATH="/opt/hermes/venv/bin:/opt/hermes/app/node_modules/.bin:${PATH}"
ENV HERMES_HOME=/data/hermes
ENV PYTHONUNBUFFERED=1

WORKDIR /opt/hermes/app

# Install Chromium for browser automation
RUN npx agent-browser install --with-deps || true

# Entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create hermes user with Unraid-compatible UID/GID (nobody:users = 99:100)
RUN groupadd -g 100 hermes 2>/dev/null || true \
    && useradd -u 99 -g 100 -m -s /bin/bash hermes \
    && echo "hermes ALL=(ALL) NOPASSWD: /usr/sbin/sshd" >> /etc/sudoers \
    && mkdir -p /data/hermes \
    && chown -R 99:100 /data/hermes

EXPOSE 22

USER hermes

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gateway"]
