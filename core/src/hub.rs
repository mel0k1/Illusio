use serde::Serialize;
use std::collections::HashSet;
use std::thread;
use std::time::{Duration, Instant};

pub const DEFAULT_HUB_URL: &str = "https://hub.spacestation14.com/";
pub const FALLBACK_HUB_URL: &str = "https://hub.fallback.spacestation14.com/";

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

#[derive(Debug, Clone, Default, Serialize)]
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

fn value_string(value: Option<&serde_json::Value>) -> String {
    match value {
        Some(serde_json::Value::String(text)) => text.clone(),
        Some(serde_json::Value::Number(number)) => number.to_string(),
        _ => String::new(),
    }
}

fn value_int(value: Option<&serde_json::Value>) -> i64 {
    match value {
        Some(serde_json::Value::Number(number)) => number
            .as_i64()
            .or_else(|| number.as_f64().map(|value| value as i64))
            .unwrap_or(0),
        Some(serde_json::Value::String(text)) => text.trim().parse().unwrap_or(0),
        _ => 0,
    }
}

fn value_bool(value: Option<&serde_json::Value>) -> bool {
    matches!(value, Some(serde_json::Value::Bool(true)))
}

fn value_strings(value: Option<&serde_json::Value>) -> Vec<String> {
    match value {
        Some(serde_json::Value::Array(items)) => items
            .iter()
            .filter_map(|item| item.as_str())
            .map(|text| text.trim().to_string())
            .filter(|text| !text.is_empty())
            .collect(),
        _ => Vec::new(),
    }
}

fn status_object(
    entry: &serde_json::Map<String, serde_json::Value>,
) -> Option<&serde_json::Map<String, serde_json::Value>> {
    entry
        .get("statusData")
        .or_else(|| entry.get("status"))
        .and_then(|value| value.as_object())
}

fn hub_server_from_value(value: &serde_json::Value) -> Option<HubServer> {
    let entry = value.as_object()?;
    let address = value_string(entry.get("address").or_else(|| entry.get("url")))
        .trim()
        .to_string();
    if address.is_empty() {
        return None;
    }
    let status = status_object(entry);
    Some(HubServer {
        address,
        name: value_string(status.and_then(|status| status.get("name"))),
        players: value_int(status.and_then(|status| status.get("players"))),
        soft_max_players: value_int(status.and_then(|status| status.get("soft_max_players"))),
        tags: merge_tags(
            value_strings(status.and_then(|status| status.get("tags"))),
            value_strings(entry.get("inferredTags")),
        ),
        preset: value_string(status.and_then(|status| status.get("preset"))),
        map: value_string(status.and_then(|status| status.get("map"))),
        run_level: value_int(status.and_then(|status| status.get("run_level"))),
        round_id: value_int(status.and_then(|status| status.get("round_id"))),
        status_message: value_string(status.and_then(|status| status.get("statusMessage"))),
        round_start_time: value_string(
            status
                .and_then(|status| status.get("round_start_time"))
                .or_else(|| status.and_then(|status| status.get("roundStartTime"))),
        ),
        panic_bunker: value_bool(status.and_then(|status| status.get("panic_bunker"))),
        baby_jail: value_bool(status.and_then(|status| status.get("baby_jail"))),
        queue: value_int(status.and_then(|status| status.get("queue"))),
        hub: String::new(),
    })
}

fn body_snippet(body: &str) -> String {
    let flat: String = body
        .chars()
        .map(|character| {
            if character.is_whitespace() {
                ' '
            } else {
                character
            }
        })
        .collect();
    let trimmed = flat.trim();
    let mut snippet: String = trimmed.chars().take(96).collect();
    if trimmed.chars().count() > 96 {
        snippet.push('…');
    }
    snippet
}

pub fn parse_hub_body(body: &str) -> Result<Vec<HubServer>, String> {
    let trimmed = body.trim();
    let array = if trimmed.starts_with('[') {
        trimmed
    } else {
        let start = trimmed.find('[');
        let end = trimmed.rfind(']');
        match (start, end) {
            (Some(start), Some(end)) if end > start => &trimmed[start..=end],
            _ => {
                return Err(format!(
                    "не удалось разобрать список серверов (ответ: {})",
                    body_snippet(trimmed)
                ))
            }
        }
    };
    let entries: Vec<serde_json::Value> = serde_json::from_str(array).map_err(|_| {
        format!(
            "не удалось разобрать список серверов (ответ: {})",
            body_snippet(trimmed)
        )
    })?;
    Ok(entries.iter().filter_map(hub_server_from_value).collect())
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

const HUB_ATTEMPTS: usize = 2;
const HUB_RETRY_PAUSE: Duration = Duration::from_millis(600);

fn hub_client() -> Result<reqwest::blocking::Client, String> {
    crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Launcher,
    )
    .timeout(Duration::from_secs(20))
    .build()
    .map_err(|error| error.to_string())
}

fn fetch_once(
    client: &reqwest::blocking::Client,
    endpoint: &str,
) -> Result<Vec<HubServer>, String> {
    let response = client
        .get(endpoint)
        .send()
        .map_err(|error| format!("хаб недоступен: {error}"))?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("хаб ответил с ошибкой: {error}"))?;
    let body = response
        .text()
        .map_err(|error| format!("хаб оборвал ответ: {error}"))?;
    parse_hub_body(&body)
}

fn fetch_hub_at(hub: &str) -> Result<Vec<HubServer>, String> {
    let client = hub_client()?;
    let endpoint = format!("{}api/servers", hub_url(hub));
    let mut last_error = String::new();
    for attempt in 0..HUB_ATTEMPTS {
        if attempt > 0 {
            thread::sleep(HUB_RETRY_PAUSE);
        }
        match fetch_once(&client, &endpoint) {
            Ok(servers) => return Ok(servers),
            Err(error) => last_error = error,
        }
    }
    Err(last_error)
}

pub fn fetch_servers(hub: &str) -> Result<Vec<HubServer>, String> {
    fetch_hub_servers(hub)
}

pub fn fetch_servers_multi(hubs: &[String]) -> Result<(Vec<HubServer>, Vec<String>), String> {
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
    let mut warnings: Vec<String> = Vec::new();
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
            Err(message) => warnings.push(message),
        }
    }
    if merged.is_empty() {
        if warnings.is_empty() {
            return Ok((merged, warnings));
        }
        return Err(warnings.join("; "));
    }
    merged.sort_by(|left, right| {
        right
            .players
            .cmp(&left.players)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
    });
    Ok((merged, warnings))
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
        let servers = parse_hub_body(raw).unwrap();
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
        let servers = parse_hub_body(raw).unwrap();
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
    fn skips_junk_and_coerces_types() {
        let raw = r#"[
            42,
            null,
            "string entry",
            {"statusData":{"name":"no address"}},
            {"address":"ss14://a.example","statusData":"offline","inferredTags":["lang:ru",null,""]},
            {"address":"ss14://b.example","statusData":{"name":"B","players":12.7,"soft_max_players":"40","tags":["rp:lrp",null],"queue":"3","panic_bunker":1}}
        ]"#;
        let servers = parse_hub_body(raw).unwrap();
        assert_eq!(servers.len(), 2);
        assert_eq!(servers[0].address, "ss14://a.example");
        assert!(servers[0].name.is_empty());
        assert_eq!(servers[0].tags, vec!["lang:ru"]);
        assert_eq!(servers[0].players, 0);
        assert_eq!(servers[1].name, "B");
        assert_eq!(servers[1].players, 12);
        assert_eq!(servers[1].soft_max_players, 40);
        assert_eq!(servers[1].tags, vec!["rp:low"]);
        assert_eq!(servers[1].queue, 3);
        assert!(!servers[1].panic_bunker);
    }

    #[test]
    fn empty_list_is_valid() {
        assert!(parse_hub_body("[]").unwrap().is_empty());
        assert!(parse_hub_body("  \n[] ").unwrap().is_empty());
    }

    #[test]
    fn extracts_array_from_wrapped_body() {
        let servers = parse_hub_body(
            "сервер вернул {\"ok\":true} [ {\"address\":\"ss14://a.example\",\"statusData\":{\"name\":\"A\"}} ] конец",
        )
        .unwrap();
        assert_eq!(servers.len(), 1);
        assert_eq!(servers[0].name, "A");
    }

    #[test]
    fn garbage_body_reports_snippet() {
        let error = parse_hub_body("<html>access denied</html>").unwrap_err();
        assert!(error.contains("не удалось разобрать список серверов"));
        assert!(error.contains("access denied"));
    }

    #[test]
    fn accepts_status_alias_and_url_field() {
        let raw = r#"[{"url":"ss14://a.example","status":{"name":"A","players":5}}]"#;
        let servers = parse_hub_body(raw).unwrap();
        assert_eq!(servers.len(), 1);
        assert_eq!(servers[0].address, "ss14://a.example");
        assert_eq!(servers[0].name, "A");
        assert_eq!(servers[0].players, 5);
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
