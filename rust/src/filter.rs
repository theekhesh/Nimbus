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
