# Nimbus — A Lightweight, Privacy-First Linux Browser

Nimbus is a modern, performance-oriented browser for Linux that prioritizes privacy, minimalism, and a beautiful native UI. Nimbus is designed to be small and fast while providing the features users expect from a modern browser: multi-tab browsing, robust resource/request interception for ad/tracker blocking, per-site privacy controls, secure networking, and an extensible UI. The project is intended to be easy to develop in resource-limited environments (e.g., GitHub Codespaces) via a fast prototype workflow, then migrated to a production-quality Rust/GTK shell for performance and memory safety.

## Goals (technical)
- Minimal footprint: keep binary/disk size and runtime memory usage low compared to mainstream browsers.
- Privacy-first defaults: block third-party cookies, ship with curated filter lists, disable telemetry/prefetching, and support DNS-over-HTTPS/DoH.
- Fast startup & runtime: lazy-init heavy components, use efficient filter indexes, and optimize builds (LTO/thin-LTO, strip, PGO when possible).
- Native Linux UX: GTK4-based UI with a modern headerbar, tabstrip, and theming support.
- Secure by design: preserve renderer sandboxing (via WebKit2), minimize C/C++ surface area, and implement critical components in Rust.
- Extensible: modular blocklist/filter engine and pluggable privacy policies, enabling incremental feature growth.

## High-level architecture
- UI shell (Rust + GTK4)
  - Tab management, address bar, history/bookmarks, settings, and UI theming.
  - Typed configuration, safe concurrency, and modern async constructs.
- Rendering engine (WebKitGTK / WebKit2)
  - Multi-process rendering model; whisper-thin embedding layer.
  - Use request/response hooks to implement blocking and privacy policies.
- Network & privacy layer
  - In-process request filtering (EasyList/EasyPrivacy parsing and index).
  - Optional DoH/DoT resolver, first-party-only cookie policy, storage partitioning.
- Filter engine
  - Pre-compiled index of filter rules for O(1) or log-time matches.
  - Rule update subsystem (fetch, verify, delta apply).
- Persistence
  - Compact local databases for settings, cache, and filter indexes (SQLite or simple binary formats).
- Tooling
  - Dev prototype (Python + WebKit2GTK) for rapid iteration.
  - Production implementation (Rust) for performance and safety.
  - CI pipeline for headless tests, visual regression (screenshots), and nightly filter updates.

## Key technical features
- Request interception and blocking at the WebKit resource level (no external proxy required).
- Per-site privacy toggles: allowlist/blocklist, cookie policy, JS enable/disable, fingerprint protections.
- Built-in filter update mechanism with verification and incremental updates.
- Optional DoH configuration and local DNS caching.
- Themeable GTK4 UI with CSS-driven styles and smooth animations.
- Focus on Linux: native packaging (tar, .deb, AppImage) and distribution-friendly artifacts.

## Development: Codespaces-friendly quick start
Nimbus is designed to be prototyped in Codespaces using a devcontainer. The canonical fast path is:
1. Use the included `.devcontainer/` (Dockerfile + devcontainer.json + setup.sh) to provision an environment with GTK/WebKit system libs and developer toolchain.
2. Run the lightweight Python prototype for UI/feature iteration, viewable via headless X or VNC/noVNC.

Example quick run for the prototype inside the devcontainer:
- Start headless X:
  - Xvfb :99 -screen 0 1280x800x24 & export DISPLAY=:99
- Run the prototype:
  - python3 prototype/browser.py
- (Optional) Expose the display with x11vnc + noVNC to interact with the UI from your browser:
  - x11vnc -display :99 -forever -nopw -shared &
  - /usr/share/novnc/utils/launch.sh --vnc localhost:5900 --listen 6080 &

Notes:
- The Python prototype demonstrates WebKit embedding and request interception for fast iteration. It is intentionally small and not optimized for production.
- For production, the main application is implemented in Rust. See the `rust/` directory for the GTK4 + webkit2gtk skeleton and build instructions.

## Build / Runtime requirements (Linux)
- System libs (development headers)
  - libgtk-4-dev, libwebkit2gtk-4.1-dev, pkg-config, libglib2.0-dev, libgdk-pixbuf2.0-dev
- Toolchain
  - Rust toolchain (rustup), cargo; or Python3 + PyGObject for prototype.
- Recommended for building release: clang/clang-tools, lld, build-essential, ccache.
- Resource guidance: prototype runs easily in Codespaces; production builds (release with LTO/PGO) benefit from >=8–16 GB RAM and sufficient disk.

## Build hints & performance tuning
- Use thin-LTO for a strong size/speed tradeoff; enable full LTO if memory allows.
- Use ccache for iterative builds and store the cache persistently in Codespaces (mounted volume).
- Consider PGO for hot-path JS/DOM code paths after profiling.
- Pre-compile filter lists into a binary index to avoid runtime parsing overhead.
- Strip binaries and remove unused symbols for distribution artifacts.

## Privacy & security considerations
- Default to block third-party cookies and disable telemetry and prefetch features.
- Keep WebKit’s sandboxing enabled; minimize enabling features that require elevated privileges.
- Carefully review any third-party native libraries for CVE history.
- Provide per-site exceptions and a clear UI for privacy controls; log minimal telemetry (or opt-in only) and document collection policy in the README.

## Roadmap (high-level)
- MVP: Rust + GTK4 skeleton, WebKit2 integration, URL blocking via local filter index, per-site privacy toggles.
- Next: DoH resolver, cookie partitioning, cosmetic filtering, filter auto-updates, UI polish.
- Later: Extension support (lightweight, scoped API), packaging, Windows/macOS ports (optional), PGO/LTO optimizations.

## Contributing & development process
- Follow the repository’s CONTRIBUTING.md for branch, commit, and review guidelines.
- Keep the filter engine modular and testable; add unit tests for rule parsing and matching.
- Add headless tests that load representative pages and assert blocking/whitelisting behavior.
- Use the devcontainer for reproducible local development and debugging.

## License & acknowledgements
Nimbus is under GNU General Public License v3.0. Nimbus uses WebKitGTK (LGPL/MPL depending on platform versions) and respects the licenses of embedded components; see LICENSE and THIRD-PARTY.md for details.
