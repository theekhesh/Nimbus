FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl wget ca-certificates pkg-config sudo \
    python3 python3-venv python3-pip python3-dev python3-gi python3-gi-cairo \
    gir1.2-gtk-4.0 gir1.2-webkit2-4.1 gir1.2-javascriptcoregtk-4.1 \
    libgtk-4-dev libwebkit2gtk-4.1-dev libglib2.0-dev libsoup-3.0-dev \
    libssl-dev libsqlite3-dev clang lld ccache zstd sqlite3 \
    xvfb x11vnc novnc websockify tmux unzip net-tools procps \
    && rm -rf /var/lib/apt/lists/*
ARG USER=vscode
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} ${USER} || true \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USER} \
 && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER}
USER ${USER}
WORKDIR /home/${USER}
ENV PATH="/home/${USER}/.cargo/bin:/home/${USER}/.local/bin:${PATH}"
