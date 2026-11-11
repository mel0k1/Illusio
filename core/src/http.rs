use crate::config::ProxyConfig;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use sha2::Digest;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

static PROXY_SESSION_OFF: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Route {
    Launcher,
    Updates,
    Region,
}

pub fn user_agent() -> String {
    format!("SS14.Launcher/{}", env!("CARGO_PKG_VERSION"))
}

pub fn fingerprint() -> String {
    static FINGERPRINT: OnceLock<String> = OnceLock::new();
    FINGERPRINT
        .get_or_init(|| {
            let dir = match crate::config::config_dir() {
                Some(value) => value,
                None => return String::new(),
            };
            let file = dir.join("fingerprint");
            if let Ok(existing) = std::fs::read_to_string(&file) {
                let trimmed = existing.trim().to_string();
                if trimmed.len() == 32 && trimmed.chars().all(|c| c.is_ascii_hexdigit()) {
                    return trimmed;
                }
            }
            let mut hasher = sha2::Sha256::new();
            hasher.update(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|value| value.as_nanos())
                    .unwrap_or(0)
                    .to_le_bytes(),
            );
            hasher.update(std::process::id().to_le_bytes());
            let digest = hasher.finalize();
            let hex: String = digest
                .iter()
                .take(16)
                .map(|byte| format!("{byte:02x}"))
                .collect();
            if std::fs::create_dir_all(&dir).is_ok() {
                let _ = std::fs::write(&file, &hex);
            }
            hex
        })
        .clone()
}

pub fn set_session_proxy(enabled: bool) {
    PROXY_SESSION_OFF.store(!enabled, Ordering::Relaxed);
}

pub fn session_proxy_enabled() -> bool {
    !PROXY_SESSION_OFF.load(Ordering::Relaxed)
}

pub fn with_route(
    builder: reqwest::blocking::ClientBuilder,
    route: Route,
) -> reqwest::blocking::ClientBuilder {
    let builder = builder.user_agent(user_agent());
    let builder = match fingerprint_headers() {
        Some(headers) => builder.default_headers(headers),
        None => builder,
    };
    if !session_proxy_enabled() {
        return builder;
    }
    let proxy = crate::config::load()
        .map(|value| value.proxy())
        .unwrap_or_default();
    if !route_enabled(&proxy, route) {
        return builder;
    }
    apply_proxy(builder, proxy)
}

fn fingerprint_headers() -> Option<HeaderMap> {
    let value = fingerprint();
    if value.is_empty() {
        return None;
    }
    let name = HeaderName::from_bytes(b"x-illusio-fingerprint").ok()?;
    let parsed = HeaderValue::from_str(&value).ok()?;
    let mut headers = HeaderMap::new();
    headers.insert(name, parsed);
    Some(headers)
}

pub fn route_enabled(proxy: &ProxyConfig, route: Route) -> bool {
    match route {
        Route::Launcher => proxy.launcher,
        Route::Updates => proxy.launcher || proxy.updates,
        Route::Region => proxy.launcher || proxy.region,
    }
}

fn apply_proxy(
    builder: reqwest::blocking::ClientBuilder,
    proxy: ProxyConfig,
) -> reqwest::blocking::ClientBuilder {
    match crate::socks::proxy_url(&proxy) {
        Some(url) => match reqwest::Proxy::all(&url) {
            Ok(value) => builder.proxy(value),
            Err(error) => {
                // Пользователь настроил прокси, но URL не собрали — молча
                // отключать его нельзя, предупреждаем и идём без прокси.
                eprintln!("illusio: не удалось применить прокси {url}: {error}");
                builder
            }
        },
        None => builder,
    }
}

#[cfg(test)]
mod tests {
    use crate::config::ProxyConfig;

    fn proxy(launcher: bool, updates: bool, region: bool) -> ProxyConfig {
        ProxyConfig {
            launcher,
            updates,
            region,
            host: "127.0.0.1".into(),
            port: 1080,
            ..Default::default()
        }
    }

    #[test]
    fn routes_combine() {
        let value = proxy(true, false, false);
        assert!(super::route_enabled(&value, super::Route::Launcher));
        assert!(super::route_enabled(&value, super::Route::Updates));
        assert!(super::route_enabled(&value, super::Route::Region));
        let value = proxy(false, true, false);
        assert!(!super::route_enabled(&value, super::Route::Launcher));
        assert!(super::route_enabled(&value, super::Route::Updates));
        assert!(!super::route_enabled(&value, super::Route::Region));
        let value = proxy(false, false, true);
        assert!(super::route_enabled(&value, super::Route::Region));
        assert!(!super::route_enabled(&value, super::Route::Updates));
    }

    #[test]
    fn proxy_url_requires_host_and_port() {
        let value = ProxyConfig {
            launcher: true,
            ..Default::default()
        };
        assert!(super::route_enabled(&value, super::Route::Launcher));
        assert!(crate::socks::proxy_url(&value).is_none());
        let value = ProxyConfig {
            host: "127.0.0.1".into(),
            port: 1080,
            ..value
        };
        assert_eq!(
            crate::socks::proxy_url(&value).as_deref(),
            Some("socks5h://127.0.0.1:1080")
        );
        let value = ProxyConfig {
            username: "user".into(),
            password: "p@ss".into(),
            ..value
        };
        assert_eq!(
            crate::socks::proxy_url(&value).as_deref(),
            Some("socks5h://user:p%40ss@127.0.0.1:1080")
        );
    }

    #[test]
    fn udp_parsing_covers_variants() {
        assert_eq!(
            crate::socks::parse_udp_address("udp://game.example.com:1212"),
            Some(("game.example.com".into(), 1212))
        );
        assert_eq!(
            crate::socks::parse_udp_address("udp://game.example.com"),
            Some(("game.example.com".into(), 1212))
        );
        assert_eq!(
            crate::socks::parse_udp_address("udp://127.0.0.1:4002/"),
            Some(("127.0.0.1".into(), 4002))
        );
        assert!(crate::socks::parse_udp_address("tcp://game.example.com").is_none());
    }

    #[test]
    fn udp_framing_roundtrip() {
        use std::net::{IpAddr, Ipv4Addr, SocketAddr};
        let target = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 0, 2, 10)), 1212);
        let framed = crate::socks::frame_udp(target, b"payload");
        assert_eq!(framed[0..3], [0, 0, 0]);
        assert_eq!(framed[3], 1);
        assert_eq!(
            crate::socks::parse_udp(&framed),
            Some(b"payload".as_slice())
        );
        assert_eq!(crate::socks::parse_udp(b"raw"), None);
    }
}
