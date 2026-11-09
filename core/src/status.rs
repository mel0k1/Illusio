use serde::{Deserialize, Serialize};
use std::time::Duration;

use crate::hub::normalize_server_address;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ServerStatus {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub status_message: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default, rename = "softMaxPlayers")]
    pub soft_max_players: i64,
    #[serde(default, rename = "playerCount")]
    pub player_count: i64,
    #[serde(default, rename = "roundStartTime", alias = "round_start_time")]
    pub round_start_time: String,
}

pub fn status_url(server_url: &str) -> String {
    format!(
        "{}/status",
        normalize_server_address(server_url).trim_end_matches('/')
    )
}

pub fn fetch_status(server_url: &str) -> Result<ServerStatus, String> {
    let client = crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Launcher,
    )
    .timeout(Duration::from_secs(15))
    .build()
    .map_err(|error| error.to_string())?;
    let response = client
        .get(status_url(server_url))
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("сервер ответил с ошибкой: {error}"))?;
    response
        .json::<ServerStatus>()
        .map_err(|error| format!("не удалось разобрать статус: {error}"))
}
