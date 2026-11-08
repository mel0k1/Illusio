use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::thread;
use std::time::{Duration, Instant};

pub const DEFAULT_HUB_URL: &str = "https://hub.spacestation14.com/";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HubServer {
    #[serde(default)]
    pub address: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub players: i64,
    #[serde(default)]
    pub soft_max_players: i64,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub preset: String,
    #[serde(default)]
    pub map: String,
    #[serde(default)]
    pub run_level: i64,
    #[serde(default)]
    pub round_id: i64,
    #[serde(default)]
    pub status_message: String,
    #[serde(default)]
    pub hub: String,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct ServerPing {
    #[serde(rename = "url")]
    pub url: String,
    #[serde(rename = "ms")]
    pub ping_ms: u64,
    #[serde(rename = "online")]
    pub online: bool,
}

#[derive(Debug, Deserialize)]
struct HubEntry {
    #[serde(default)]
    address: String,
    #[serde(default, rename = "statusData")]
    status_data: HubStatusData,
}

#[derive(Debug, Deserialize, Default)]
struct HubStatusData {
    #[serde(default)]
    name: String,
    #[serde(default)]
    players: i64,
    #[serde(default, rename = "soft_max_players")]
    soft_max_players: i64,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    preset: String,
    #[serde(default)]
    map: String,
    #[serde(default, rename = "run_level")]
    run_level: i64,
    #[serde(default, rename = "round_id")]
    round_id: i64,
    #[serde(default, rename = "statusMessage")]
    status_message: String,
}

pub fn normalize_server_address(server_url: &str) -> String {
    let trimmed = server_url.trim();
    if let Some(rest) = trimmed.strip_prefix("ss14s://") {
        return format!("https://{rest}");
    }
    if let Some(rest) = trimmed.strip_prefix("ss14://") {
        return format!("http://{rest}");
    }
    trimmed.to_string()
}

impl From<HubEntry> for HubServer {
    fn from(entry: HubEntry) -> Self {
        let status = entry.status_data;
        HubServer {
            address: entry.address,
            name: status.name,
            players: status.players,
            soft_max_players: status.soft_max_players,
            tags: status.tags,
            preset: status.preset,
            map: status.map,
            run_level: status.run_level,
            round_id: status.round_id,
            status_message: status.status_message,
            hub: String::new(),
        }
    }
}

pub fn hub_url(value: &str) -> String {
    let trimmed = value.trim();
    let url = if trimmed.is_empty() {
        DEFAULT_HUB_URL.to_string()
    } else {
        trimmed.to_string()
    };
    if url.ends_with('/') {
        url
    } else {
        format!("{url}/")
    }
}

fn fetch_hub_servers(hub: &str) -> Result<Vec<HubServer>, String> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|error| error.to_string())?;
    let endpoint = format!("{}api/servers", hub_url(hub));
    let response = client
        .get(endpoint)
        .send()
        .map_err(|error| format!("хаб недоступен: {error}"))?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("хаб ответил с ошибкой: {error}"))?;
    let entries: Vec<HubEntry> = response
        .json()
        .map_err(|error| format!("не удалось разобрать список серверов: {error}"))?;
    Ok(entries.into_iter().map(HubServer::from).collect())
}

pub fn fetch_servers(hub: &str) -> Result<Vec<HubServer>, String> {
    fetch_hub_servers(hub)
}

pub fn fetch_servers_multi(hubs: &[String]) -> Result<Vec<HubServer>, String> {
    let mut jobs: Vec<(String, String)> = vec![(DEFAULT_HUB_URL.to_string(), String::new())];
    for hub in hubs {
        let url = hub_url(hub);
        if url == DEFAULT_HUB_URL || jobs.iter().any(|(existing, _)| *existing == url) {
            continue;
        }
        jobs.push((url.clone(), url));
    }
    let results: Vec<Result<Vec<HubServer>, String>> = thread::scope(|scope| {
        let handles: Vec<_> = jobs
            .iter()
            .map(|(url, label)| {
                let url = url.clone();
                let label = label.clone();
                scope.spawn(move || {
                    fetch_hub_servers(&url).map(|mut servers| {
                        for server in servers.iter_mut() {
                            if !label.is_empty() {
                                server.hub = label.clone();
                            }
                        }
                        servers
                    })
                })
            })
            .collect();
        handles
            .into_iter()
            .map(|handle| handle.join().unwrap())
            .collect()
    });
    let mut merged: Vec<HubServer> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    let mut errors: Vec<String> = Vec::new();
    for result in results {
        match result {
            Ok(servers) => {
                for server in servers {
                    let key = server.address.trim().to_ascii_lowercase();
                    if key.is_empty() || !seen.insert(key) {
                        continue;
                    }
                    merged.push(server);
                }
            }
            Err(message) => errors.push(message),
        }
    }
    if merged.is_empty() {
        if errors.is_empty() {
            return Ok(merged);
        }
        return Err(errors.join("; "));
    }
    Ok(merged)
}

fn ping_client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(5))
        .connect_timeout(Duration::from_secs(5))
        .build()
        .map_err(|error| error.to_string())
}

pub fn ping_server(url: &str) -> ServerPing {
    let address = normalize_server_address(url);
    let endpoint = format!("{}/status", address.trim_end_matches('/'));
    let client = match ping_client() {
        Ok(client) => client,
        Err(_) => {
            return ServerPing {
                url: url.to_string(),
                ping_ms: 0,
                online: false,
            }
        }
    };
    let started = Instant::now();
    let online = client
        .get(endpoint)
        .send()
        .map(|response| response.status().is_success())
        .unwrap_or(false);
    ServerPing {
        url: url.to_string(),
        ping_ms: started.elapsed().as_millis() as u64,
        online,
    }
}

pub fn ping_servers(urls: &[String]) -> Vec<ServerPing> {
    thread::scope(|scope| {
        let handles: Vec<_> = urls
            .iter()
            .map(|url| {
                let url = url.clone();
                scope.spawn(move || ping_server(&url))
            })
            .collect();
        handles
            .into_iter()
            .map(|handle| handle.join().unwrap())
            .collect()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_schemes() {
        assert_eq!(
            normalize_server_address("ss14s://cinka.ru/meow/3d"),
            "https://cinka.ru/meow/3d"
        );
        assert_eq!(
            normalize_server_address("ss14://wormix14.site"),
            "http://wormix14.site"
        );
        assert_eq!(
            normalize_server_address("https://example.com"),
            "https://example.com"
        );
    }

    #[test]
    fn parses_hub_payload() {
        let raw = r#"[
            {"address":"ss14://wormix14.site","statusData":{"name":"Wormix","players":32,"soft_max_players":40,"tags":["lang:ru"],"preset":"Гриншифт","map":"Box","run_level":1,"round_id":1437,"statusMessage":"привет"}},
            {"address":"ss14s://erida.example.net","statusData":{"name":"Эрида","players":25}}
        ]"#;
        let servers: Vec<HubServer> = serde_json::from_str::<Vec<HubEntry>>(raw)
            .unwrap()
            .into_iter()
            .map(HubServer::from)
            .collect();
        assert_eq!(servers.len(), 2);
        assert_eq!(servers[0].players, 32);
        assert_eq!(servers[0].soft_max_players, 40);
        assert_eq!(servers[0].status_message, "привет");
        assert_eq!(servers[1].soft_max_players, 0);
    }

    #[test]
    fn hub_url_appends_slash() {
        assert_eq!(hub_url(""), DEFAULT_HUB_URL);
        assert_eq!(
            hub_url("https://hub.example.com"),
            "https://hub.example.com/"
        );
    }

    #[test]
    fn ping_payload_serializes() {
        let ping = ServerPing {
            url: "ss14://wormix14.site".into(),
            ping_ms: 42,
            online: true,
        };
        let raw = serde_json::to_string(&ping).unwrap();
        assert!(raw.contains("\"url\":\"ss14://wormix14.site\""));
        assert!(raw.contains("\"ms\":42"));
        assert!(raw.contains("\"online\":true"));
    }
}
