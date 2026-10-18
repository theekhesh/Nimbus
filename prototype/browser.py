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
