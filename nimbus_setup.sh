#!/usr/bin/env bash
# nimbus_setup.sh - Single-file installer for Nimbus browser dev environment
# Target: GitHub Codespaces on Ubuntu 24.04 (Noble)
# Usage: chmod +x nimbus_setup.sh && ./nimbus_setup.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[nimbus]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ warn ]${NC} $*"; }
die()  { echo -e "${RED}[ fail ]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Do not run as root. Run as the 'vscode' user."
command -v sudo >/dev/null || die "sudo is required."
command -v apt-get >/dev/null || die "This script targets Debian/Ubuntu."

WORKSPACE="${WORKSPACE:-$(pwd)}"
log "Workspace: $WORKSPACE"

# ------------------------------------------------------------------
# 1. System packages (Noble-correct names)
# ------------------------------------------------------------------
log "Installing system dependencies..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential git curl wget ca-certificates pkg-config \
    python3 python3-venv python3-pip python3-dev \
    python3-gi python3-gi-cairo \
    libgirepository-2.0-dev \
    gir1.2-gtk-4.0 gir1.2-webkit2-4.1 gir1.2-javascriptcoregtk-4.1 \
    libgirepository-2.0-dev libgtk-4-dev libwebkit2gtk-4.1-dev libglib2.0-dev \
    libgdk-pixbuf-2.0-dev libsoup-3.0-dev libssl-dev \
    libsqlite3-dev libdbus-1-dev \
    clang lld ccache zstd sqlite3 \
    xvfb x11vnc novnc websockify net-tools procps tmux unzip \
    >/dev/null
ok "System packages installed."

# ------------------------------------------------------------------
# 2. Rust toolchain
# ------------------------------------------------------------------
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
    log "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal >/dev/null
    ok "Rust installed."
else
    ok "Rust already present."
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustup component add rustfmt clippy >/dev/null 2>&1 || true

# ------------------------------------------------------------------
# 3. Python prototype deps (PEP-668 safe)
# ------------------------------------------------------------------
log "Installing Python prototype dependencies..."
python3 -m pip install --user --quiet --break-system-packages pygobject >/dev/null
ok "Python deps installed."

# ------------------------------------------------------------------
# 4. Repo skeleton (idempotent)
# ------------------------------------------------------------------
cd "$WORKSPACE"
mkdir -p .devcontainer prototype rust/src rust/filters ci packaging docs

if [ ! -f prototype/browser.py ]; then
cat > prototype/browser.py <<'PYEOF'
#!/usr/bin/env python3
"""Nimbus prototype: GTK4 + WebKit2 (4.1) with naive host blocking.
Run headless: Xvfb :99 & export DISPLAY=:99 && python3 prototype/browser.py"""
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gtk, WebKit2

BLOCKLIST = {
    "doubleclick.net", "googlesyndication.com",
    "adservice.google.com", "ads.example.com",
    "facebook.com/tr", "scorecardresearch.com",
}

def is_blocked(uri: str) -> bool:
    return any(b in uri for b in BLOCKLIST)

class Nimbus(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Nimbus")
        self.set_default_size(1200, 800)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.set_child(box)

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self.url = Gtk.Entry()
        self.url.set_hexpand(True)
        self.url.set_text("https://example.org")
        self.url.connect("activate", self.navigate)
        go = Gtk.Button(label="Go")
        go.connect("clicked", self.navigate)
        bar.append(self.url); bar.append(go)
        box.append(bar)

        self.web = WebKit2.WebView()
        self.web.connect("decide-policy", self.on_policy)
        scroller = Gtk.ScrolledWindow()
        scroller.set_child(self.web)
        scroller.set_vexpand(True)
        box.append(scroller)

    def navigate(self, *_):
        u = self.url.get_text().strip()
        if not u.startswith(("http://", "https://")):
            u = "https://" + u
        self.web.load_uri(u)

    def on_policy(self, _view, decision, _dtype):
        try:
            req = decision.get_request()
            if req and is_blocked(req.get_uri()):
                decision.ignore()
                return True
        except Exception:
            pass
        try: decision.use()
        except Exception: pass
        return False

class NimbusApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="com.nimbus.prototype")
    def do_activate(self):
        Nimbus(self).present()

if __name__ == "__main__":
    NimbusApp().run(None)
PYEOF
ok "Created prototype/browser.py"
fi

# ---- Cargo.toml (matched gtk4 0.9 + webkit2gtk 2.0 = WebKitGTK 4.1) ----
if [ ! -f rust/Cargo.toml ]; then
cat > rust/Cargo.toml <<'TOMLEOF'
[package]
name = "nimbus"
version = "0.1.0"
edition = "2021"
description = "Nimbus: a lightweight, privacy-first Linux browser"

[dependencies]
gtk4 = "0.9"
webkit2gtk = "2.0"
glib = "0.20"
once_cell = "1.19"
parking_lot = "0.12"
url = "2.5"
log = "0.4"
env_logger = "0.11"

[profile.release]
lto = "thin"
codegen-units = 1
strip = true
opt-level = 3
TOMLEOF
ok "Created rust/Cargo.toml"
fi

if [ ! -f rust/src/main.rs ]; then
cat > rust/src/main.rs <<'RSEOF'
mod filter;
mod ui;

fn main() {
    env_logger::init();
    ui::run();
}
RSEOF
ok "Created rust/src/main.rs"
fi

# ---- filter.rs: clean suffix matcher ----
if [ ! -f rust/src/filter.rs ]; then
cat > rust/src/filter.rs <<'RSEOF'
use parking_lot::RwLock;
use std::collections::HashSet;
use url::Url;

/// Minimal host-based blocking engine. Replace with an indexed
/// EasyList parser later (see docs/design.md).
pub struct FilterEngine {
    blocked: RwLock<HashSet<String>>,
}

impl FilterEngine {
    pub fn new() -> Self {
        let seed: HashSet<String> = [
            "doubleclick.net",
            "googlesyndication.com",
            "adservice.google.com",
            "scorecardresearch.com",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        Self { blocked: RwLock::new(seed) }
    }

    pub fn is_blocked(&self, uri: &str) -> bool {
        let Ok(u) = Url::parse(uri) else { return false };
        let Some(host) = u.host_str() else { return false };
        let set = self.blocked.read();
        // Check every suffix of the host: a.b.c -> a.b.c, b.c, c
        let mut start = 0usize;
        loop {
            let candidate = &host[start..];
            if set.contains(candidate) {
                return true;
            }
            match host[start..].find('.') {
                Some(pos) => start += pos + 1,
                None => break,
            }
        }
        false
    }

    pub fn add_block(&self, host: &str) {
        self.blocked.write().insert(host.to_string());
    }

    pub fn remove_block(&self, host: &str) {
        self.blocked.write().remove(host);
    }
}
RSEOF
ok "Created rust/src/filter.rs"
fi

# ---- ui.rs: correct gtk4 0.9 / webkit2gtk 2.0 API ----
if [ ! -f rust/src/ui.rs ]; then
cat > rust/src/ui.rs <<'RSEOF'
use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, Box as GtkBox, Button, Entry, Orientation, ScrolledWindow};
use std::sync::Arc;
use webkit2gtk::{PolicyDecisionExt, WebView, WebViewExt};

use crate::filter::FilterEngine;

pub fn run() {
    let app = Application::builder()
        .application_id("com.nimbus.browser")
        .build();
    app.connect_activate(build_window);
    app.run();
}

fn build_window(app: &Application) {
    let win = ApplicationWindow::builder()
        .application(app)
        .title("Nimbus")
        .default_width(1200)
        .default_height(800)
        .build();

    let vbox = GtkBox::new(Orientation::Vertical, 4);
    win.set_child(Some(&vbox));

    let bar = GtkBox::new(Orientation::Horizontal, 4);
    let entry = Entry::new();
    entry.set_hexpand(true);
    entry.set_placeholder_text(Some("https://example.org"));
    let go = Button::with_label("Go");
    bar.append(&entry);
    bar.append(&go);
    vbox.append(&bar);

    let webview = WebView::new();
    let engine = Arc::new(FilterEngine::new());
    let engine_cb = engine.clone();

    webview.connect_decide_policy(move |_wv, decision, _dtype| {
        if let Some(req) = decision.request() {
            if let Some(uri) = req.uri() {
                if engine_cb.is_blocked(&uri) {
                    decision.ignore();
                    return true;
                }
            }
        }
        let _ = decision.use_();
        false
    });

    let scroller = ScrolledWindow::new();
    scroller.set_child(Some(&webview));
    scroller.set_vexpand(true);
    vbox.append(&scroller);

    let webview_clone = webview.clone();
    let entry_clone = entry.clone();
    go.connect_clicked(move |_| {
        let mut u = entry_clone.text().to_string();
        if !u.starts_with("http://") && !u.starts_with("https://") {
            u = format!("https://{u}");
        }
        webview_clone.load_uri(&u);
    });

    webview.load_uri("https://example.org");
    win.present();
}
RSEOF
ok "Created rust/src/ui.rs"
fi

# ---- devcontainer (uses 4.1 gir) ----
if [ ! -f .devcontainer/devcontainer.json ]; then
cat > .devcontainer/devcontainer.json <<'JSONEOF'
{
  "name": "nimbus-dev",
  "build": { "dockerfile": "Dockerfile" },
  "workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}",
  "postCreateCommand": "bash ./nimbus_setup.sh || true",
  "remoteUser": "vscode",
  "forwardPorts": [6080]
}
JSONEOF
ok "Created .devcontainer/devcontainer.json"
fi

if [ ! -f .devcontainer/Dockerfile ]; then
cat > .devcontainer/Dockerfile <<'DOCKEREOF'
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl wget ca-certificates pkg-config sudo \
    python3 python3-venv python3-pip python3-dev python3-gi python3-gi-cairo \
    gir1.2-gtk-4.0 gir1.2-webkit2-4.1 gir1.2-javascriptcoregtk-4.1 \
    libgirepository-2.0-dev libgtk-4-dev libwebkit2gtk-4.1-dev libglib2.0-dev libsoup-3.0-dev \
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
DOCKEREOF
ok "Created .devcontainer/Dockerfile"
fi

if [ ! -f ci/build.yml ]; then
cat > ci/build.yml <<'YEOF'
name: build
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - name: Install deps
        run: |
          sudo apt-get update
          sudo apt-get install -y libgirepository-2.0-dev libgtk-4-dev libwebkit2gtk-4.1-dev pkg-config
      - uses: dtolnay/rust-toolchain@stable
      - name: Build
        run: cargo build --release --manifest-path=rust/Cargo.toml
      - uses: actions/upload-artifact@v4
        with:
          name: nimbus
          path: rust/target/release/nimbus
YEOF
ok "Created ci/build.yml"
fi

# ------------------------------------------------------------------
# 5. Build smoke test
# ------------------------------------------------------------------
log "Compiling Nimbus (Rust) — first build takes several minutes..."
if ( cd rust && cargo build --release 2>&1 | tail -n 25 ); then
    ok "Rust build succeeded: rust/target/release/nimbus"
else
    warn "Rust build failed — check output above. Python prototype still works."
fi

# ------------------------------------------------------------------
# 6. Headless display helper
# ------------------------------------------------------------------
cat > start_display.sh <<'SHEOF'
#!/usr/bin/env bash
set -e
Xvfb :99 -screen 0 1280x800x24 >/tmp/xvfb.log 2>&1 &
sleep 1
export DISPLAY=:99
x11vnc -display :99 -forever -nopw -shared -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/novnc.log 2>&1 &
echo "Display :99 ready. Forward port 6080 in Codespaces PORTS tab."
SHEOF
chmod +x start_display.sh

# ------------------------------------------------------------------
# 7. Summary
# ------------------------------------------------------------------
cat <<EOF

${GREEN}====================================================================
 Nimbus dev environment ready (Ubuntu 24.04 / Noble)
====================================================================${NC}

Quick start:
  # Python prototype (headless)
  Xvfb :99 -screen 0 1280x800x24 & export DISPLAY=:99
  python3 prototype/browser.py

  # Rust build
  cd rust && cargo run --release

  # Interactive GUI via noVNC (forward port 6080)
  ./start_display.sh

Key packages now used (Noble-correct):
  gir1.2-webkit2-4.1           (was: gir1.2-webkit2-4.0 — does not exist)
  gir1.2-javascriptcoregtk-4.1
  libwebkit2gtk-4.1-dev
  libsoup-3.0-dev

EOF
ok "Setup complete."