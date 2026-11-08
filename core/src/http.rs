use crate::config::ProxyConfig;

pub fn with_proxy(builder: reqwest::blocking::ClientBuilder) -> reqwest::blocking::ClientBuilder {
    let proxy = crate::config::load()
        .map(|value| value.proxy())
        .unwrap_or_default();
    apply_proxy(builder, proxy)
}

fn apply_proxy(
    builder: reqwest::blocking::ClientBuilder,
    proxy: ProxyConfig,
) -> reqwest::blocking::ClientBuilder {
    match crate::socks::proxy_url(&proxy) {
        Some(url) => match reqwest::Proxy::all(&url) {
            Ok(value) => builder.proxy(value),
            Err(_) => builder,
        },
        None => builder,
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn proxy_url_is_empty_without_host() {
        let proxy = crate::config::ProxyConfig {
            enabled: true,
            ..Default::default()
        };
        assert!(crate::socks::proxy_url(&proxy).is_none());
        let proxy = crate::config::ProxyConfig {
            enabled: true,
            host: "127.0.0.1".into(),
            port: 1080,
            ..Default::default()
        };
        assert_eq!(
            crate::socks::proxy_url(&proxy).as_deref(),
            Some("socks5h://127.0.0.1:1080")
        );
        let proxy = crate::config::ProxyConfig {
            username: "user".into(),
            password: "p@ss".into(),
            ..proxy
        };
        assert_eq!(
            crate::socks::proxy_url(&proxy).as_deref(),
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
