use gtk4::prelude::*;
use gtk4::{
    Application, ApplicationWindow, Box as GtkBox, Button, Entry, Orientation,
    ScrolledWindow,
};
use std::sync::Arc;
use webkit6::prelude::*;
use webkit6::{NavigationPolicyDecision, PolicyDecisionType, WebView};

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

    // Address bar
    let bar = GtkBox::new(Orientation::Horizontal, 4);
    let entry = Entry::new();
    entry.set_hexpand(true);
    entry.set_placeholder_text(Some("https://example.org"));
    let go = Button::with_label("Go");
    bar.append(&entry);
    bar.append(&go);
    vbox.append(&bar);

    // WebView (webkit6 = WebKitGTK 6.0, GTK4-native)
    let webview = WebView::new();
    let engine = Arc::new(FilterEngine::new());
    let engine_cb = engine.clone();

    webview.connect_decide_policy(move |_wv, decision, decision_type| {
        // Only navigation decisions carry a URIRequest we can inspect here.
        // Resource loading is better handled via the "resource-load-started" signal
        // in a production build.
        if decision_type == PolicyDecisionType::NavigationAction {
            if let Some(nav) = decision.downcast_ref::<NavigationPolicyDecision>() {
                if let Some(req) = nav.request() {
                    if let Some(uri) = req.uri() {
                        if engine_cb.is_blocked(uri.as_str()) {
                            decision.ignore();
                            return true;
                        }
                    }
                }
            }
        }

        decision.use_();
        false
    });

    let scroller = ScrolledWindow::new();
    scroller.set_child(Some(&webview));
    scroller.set_vexpand(true);
    vbox.append(&scroller);

    // Navigation handler
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