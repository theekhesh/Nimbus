#!/usr/bin/env bash
set -e
Xvfb :99 -screen 0 1280x800x24 >/tmp/xvfb.log 2>&1 &
sleep 1
export DISPLAY=:99
x11vnc -display :99 -forever -nopw -shared -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/novnc.log 2>&1 &
echo "Display :99 ready. Forward port 6080 in Codespaces PORTS tab."
