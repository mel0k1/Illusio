use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::thread;
use std::time::{Duration, Instant};

pub const DEFAULT_HUB_URL: &str = "https://hub.spacestation14.com/";
pub const FALLBACK_HUB_URL: &str = "https://hub.fallback.spacestation14.com/";

fn null_to_default<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Default + serde::Deserialize<'de>,
{
    let value: Option<T> = Option::deserialize(deserializer)?;
    Ok(value.unwrap_or_default())
}

fn normalize_tag(tag: &str) -> String {
    let clean = tag.trim().to_lowercase();
    match clean.as_str() {
        "rp:med" | "rp:mrp" => "rp:medium".to_string(),
        "rp:lrp" => "rp:low".to_string(),
        "rp:hrp" => "rp:high".to_string(),
        _ => clean,
    }
}

fn merge_tags(primary: Vec<String>, extra: Vec<String>) -> Vec<String> {
    let mut merged: Vec<String> = Vec::new();
    for tag in primary.into_iter().chain(extra) {
        let tag = normalize_tag(&tag);
        if !tag.is_empty() && !merged.contains(&tag) {
            merged.push(tag);
        }
    }
    merged
}

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
    #[serde(default, rename = "roundStartTime", alias = "round_start_time")]
    pub round_start_time: String,
    #[serde(default)]
    pub panic_bunker: bool,
    #[serde(default)]
    pub baby_jail: bool,
    #[serde(default)]
    pub queue: i64,
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
    #[serde(default, rename = "statusData", deserialize_with = "null_to_default")]
    status_data: HubStatusData,
    #[serde(default, rename = "inferredTags", deserialize_with = "null_to_default")]
    inferred_tags: Vec<String>,
}

#[derive(Debug, Deserialize, Default)]
struct HubStatusData {
    #[serde(default, deserialize_with = "null_to_default")]
    name: String,
    #[serde(default, deserialize_with = "null_to_default")]
    players: i64,
    #[serde(
        default,
        deserialize_with = "null_to_default",
        rename = "soft_max_players"
    )]
    soft_max_players: i64,
    #[serde(default, deserialize_with = "null_to_default")]
    tags: Vec<String>,
    #[serde(default, deserialize_with = "null_to_default")]
    preset: String,
    #[serde(default, deserialize_with = "null_to_default")]
    map: String,
    #[serde(default, deserialize_with = "null_to_default", rename = "run_level")]
    run_level: i64,
    #[serde(default, deserialize_with = "null_to_default", rename = "round_id")]
    round_id: i64,
    #[serde(
        default,
        deserialize_with = "null_to_default",
        rename = "statusMessage"
    )]
    status_message: String,
    #[serde(
        default,
        deserialize_with = "null_to_default",
        rename = "round_start_time",
        alias = "roundStartTime"
    )]
    round_start_time: String,
    #[serde(default, deserialize_with = "null_to_default")]
    panic_bunker: bool,
    #[serde(default, deserialize_with = "null_to_default")]
    baby_jail: bool,
    #[serde(default, deserialize_with = "null_to_default")]
    queue: i64,
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
            tags: merge_tags(status.tags, entry.inferred_tags),
            preset: status.preset,
            map: status.map,
            run_level: status.run_level,
            round_id: status.round_id,
            status_message: status.status_message,
            round_start_time: status.round_start_time,
            panic_bunker: status.panic_bunker,
            baby_jail: status.baby_jail,
            queue: status.queue,
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
    let url = hub_url(hub);
    match fetch_hub_at(&url) {
        Err(error) if url == DEFAULT_HUB_URL => fetch_hub_at(FALLBACK_HUB_URL).map_err(|_| error),
        other => other,
    }
}

fn fetch_hub_at(hub: &str) -> Result<Vec<HubServer>, String> {
    let client = crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Launcher,
    )
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
    merged.sort_by(|left, right| {
        right
            .players
            .cmp(&left.players)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
    });
    Ok(merged)
}

fn ping_client() -> Result<reqwest::blocking::Client, String> {
    crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Launcher,
    )
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
    fn tolerates_null_fields() {
        let raw = r#"[
            {"address":"ss14://a.example","statusData":{"name":"A","map":null,"preset":null,"tags":null,"round_start_time":null,"queue":null}},
            {"address":"ss14://b.example","statusData":null},
            {"address":"ss14://c.example","statusData":{"name":"C","tags":["rp:med","lang:ru"],"panic_bunker":true,"baby_jail":false},"inferredTags":["rp:med","18+"]}
        ]"#;
        let servers: Vec<HubServer> = serde_json::from_str::<Vec<HubEntry>>(raw)
            .unwrap()
            .into_iter()
            .map(HubServer::from)
            .collect();
        assert_eq!(servers.len(), 3);
        assert_eq!(servers[0].map, "");
        assert_eq!(servers[0].preset, "");
        assert!(servers[0].tags.is_empty());
        assert_eq!(servers[0].round_start_time, "");
        assert_eq!(servers[0].queue, 0);
        assert_eq!(servers[1].name, "");
        assert!(servers[1].tags.is_empty());
        assert_eq!(servers[2].tags, vec!["rp:medium", "lang:ru", "18+"]);
        assert!(servers[2].panic_bunker);
        assert!(!servers[2].baby_jail);
    }

    #[test]
    fn normalizes_rp_aliases() {
        assert_eq!(normalize_tag("rp:med"), "rp:medium");
        assert_eq!(normalize_tag("rp:mrp"), "rp:medium");
        assert_eq!(normalize_tag("rp:lrp"), "rp:low");
        assert_eq!(normalize_tag("rp:hrp"), "rp:high");
        assert_eq!(normalize_tag("rp:low"), "rp:low");
        assert_eq!(normalize_tag("lang:RU"), "lang:ru");
        assert_eq!(merge_tags(vec!["rp:med".into()], vec![]), vec!["rp:medium"]);
        assert_eq!(
            merge_tags(vec!["lang:ru".into()], vec!["lang:ru".into()]),
            vec!["lang:ru"]
        );
    }

    #[test]
    fn parses_hub_payload() {
        let raw = r#"[
            {"address":"ss14://wormix14.site","statusData":{"name":"Wormix","players":32,"soft_max_players":40,"tags":["lang:ru"],"preset":"Гриншифт","map":"Box","run_level":1,"round_id":1437,"statusMessage":"привет","round_start_time":"2026-01-01T10:00:00Z"}},
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
        assert_eq!(servers[0].round_start_time, "2026-01-01T10:00:00Z");
        assert_eq!(servers[1].soft_max_players, 0);
        assert_eq!(servers[1].round_start_time, "");
        assert!(!servers[0].panic_bunker);
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
