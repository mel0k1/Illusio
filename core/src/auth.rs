use serde::{Deserialize, Serialize};
use std::time::Duration;

pub const DEFAULT_AUTH_URL: &str = "https://auth.spacestation14.com/";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
pub struct LoginInfo {
    pub token: String,
    pub username: String,
    pub user_id: String,
    pub expire_time: String,
    pub auth_server: String,
    #[serde(default)]
    pub hwid: String,
}

#[derive(Debug, Deserialize)]
struct AuthResponse {
    token: String,
    username: String,
    #[serde(rename = "userId")]
    user_id: String,
    #[serde(rename = "expireTime")]
    expire_time: String,
}

#[derive(Debug, Deserialize)]
struct AuthDenyResponse {
    #[serde(default)]
    errors: Vec<String>,
    #[serde(default)]
    code: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct AuthError {
    pub code: String,
    pub message: String,
}

impl std::fmt::Display for AuthError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

pub fn normalize_auth_url(url: &str) -> String {
    let trimmed = url.trim();
    let value = if trimmed.is_empty() {
        DEFAULT_AUTH_URL.to_string()
    } else {
        trimmed.to_string()
    };
    if value.ends_with('/') {
        value
    } else {
        format!("{value}/")
    }
}

fn client() -> Result<reqwest::blocking::Client, String> {
    crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Launcher,
    )
    .timeout(Duration::from_secs(15))
    .build()
    .map_err(|error| error.to_string())
}

fn deny_message(code: &str, errors: &[String]) -> AuthError {
    let code_clean = code.trim().to_ascii_lowercase();
    let message = match code_clean.as_str() {
        "invalidcredentials" => "неверный логин или пароль".to_string(),
        "accountunconfirmed" => "аккаунт не подтверждён, проверьте почту".to_string(),
        "tfarequired" => "требуется код двухфакторной аутентификации".to_string(),
        "tfainvalid" => "неверный код двухфакторной аутентификации".to_string(),
        "accountlocked" => "аккаунт заблокирован".to_string(),
        _ => {
            if errors.is_empty() {
                "авторизация не удалась".to_string()
            } else {
                errors.join("; ")
            }
        }
    };
    AuthError {
        code: code_clean,
        message,
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AuthenticateBody {
    username: String,
    password: String,
    tfa_code: Option<String>,
}

pub fn authenticate(
    auth_url: &str,
    username: &str,
    password: &str,
    tfa_code: Option<&str>,
) -> Result<LoginInfo, AuthError> {
    let url = format!("{}api/auth/authenticate", normalize_auth_url(auth_url));
    let body = AuthenticateBody {
        username: username.to_string(),
        password: password.to_string(),
        tfa_code: tfa_code
            .map(|value| value.trim().to_string())
            .filter(|v| !v.is_empty()),
    };
    let client = client().map_err(|message| AuthError {
        code: "network".into(),
        message,
    })?;
    let response = client
        .post(url)
        .json(&body)
        .send()
        .map_err(|error| AuthError {
            code: "network".into(),
            message: error.to_string(),
        })?;

    if response.status().is_success() {
        let parsed: AuthResponse = response.json().map_err(|error| AuthError {
            code: "protocol".into(),
            message: format!("сервер авторизации вернул некорректный ответ: {error}"),
        })?;
        return Ok(LoginInfo {
            token: parsed.token,
            username: parsed.username,
            user_id: parsed.user_id,
            expire_time: parsed.expire_time,
            auth_server: normalize_auth_url(auth_url),
            hwid: String::new(),
        });
    }

    if response.status().as_u16() == 401 {
        let parsed: AuthDenyResponse = response.json().map_err(|error| AuthError {
            code: "protocol".into(),
            message: format!("сервер авторизации вернул некорректный ответ: {error}"),
        })?;
        return Err(deny_message(&parsed.code, &parsed.errors));
    }

    Err(AuthError {
        code: "protocol".into(),
        message: format!(
            "сервер авторизации ответил с ошибкой: {}",
            response.status()
        ),
    })
}

#[derive(Debug, Deserialize)]
struct RefreshResponse {
    #[serde(rename = "newToken")]
    new_token: String,
    #[serde(rename = "expireTime")]
    expire_time: String,
}

pub fn refresh(auth_url: &str, login: &LoginInfo) -> Result<LoginInfo, String> {
    let url = format!("{}api/auth/refresh", normalize_auth_url(auth_url));
    let client = client()?;
    let response = client
        .post(url)
        .json(&serde_json::json!({"token": login.token}))
        .send()
        .map_err(|error| error.to_string())?;

    if response.status().as_u16() == 401 {
        return Err("токен истёк, войдите заново".into());
    }
    if !response.status().is_success() {
        return Err(format!(
            "сервер авторизации ответил с ошибкой: {}",
            response.status()
        ));
    }
    let parsed: RefreshResponse = response
        .json()
        .map_err(|error| format!("сервер авторизации вернул некорректный ответ: {error}"))?;
    Ok(LoginInfo {
        token: parsed.new_token,
        username: login.username.clone(),
        user_id: login.user_id.clone(),
        expire_time: parsed.expire_time,
        auth_server: normalize_auth_url(auth_url),
        hwid: login.hwid.clone(),
    })
}

pub fn check_token(auth_url: &str, token: &str) -> Result<bool, String> {
    let url = format!("{}api/auth/ping", normalize_auth_url(auth_url));
    let client = client()?;
    let response = client
        .get(url)
        .header("Authorization", format!("SS14Auth {token}"))
        .send()
        .map_err(|error| error.to_string())?;
    let status = response.status().as_u16();
    match status {
        200 => Ok(true),
        401 => Ok(false),
        other => Err(format!("сервер авторизации ответил с ошибкой: {other}")),
    }
}

pub fn logout(auth_url: &str, token: &str) -> Result<(), String> {
    let url = format!("{}api/auth/logout", normalize_auth_url(auth_url));
    let client = client()?;
    let response = client
        .post(url)
        .json(&serde_json::json!({"token": token}))
        .send()
        .map_err(|error| error.to_string())?;
    if response.status().is_success() {
        Ok(())
    } else {
        Err(format!(
            "сервер авторизации ответил с ошибкой: {}",
            response.status()
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_auth_url() {
        assert_eq!(normalize_auth_url(""), "https://auth.spacestation14.com/");
        assert_eq!(
            normalize_auth_url("https://auth.spacestation14.com"),
            "https://auth.spacestation14.com/"
        );
        assert_eq!(
            normalize_auth_url(" https://auth.example.io/ "),
            "https://auth.example.io/"
        );
    }

    #[test]
    fn maps_deny_codes() {
        let error = deny_message("InvalidCredentials", &[]);
        assert_eq!(error.message, "неверный логин или пароль");
        let error = deny_message("TfaRequired", &[]);
        assert_eq!(error.message, "требуется код двухфакторной аутентификации");
        let error = deny_message("unknown", vec!["что-то пошло не так".into()].as_slice());
        assert_eq!(error.message, "что-то пошло не так");
        let error = deny_message("unknown", &[]);
        assert_eq!(error.message, "авторизация не удалась");
    }

    #[test]
    fn parses_auth_payloads() {
        let ok: AuthResponse = serde_json::from_str(
            r#"{"token":"t","username":"user","userId":"guid","expireTime":"2026-01-01T00:00:00Z"}"#,
        )
        .expect("parse ok");
        assert_eq!(ok.user_id, "guid");
        let deny: AuthDenyResponse = serde_json::from_str(
            r#"{"errors":["Invalid login credentials."],"code":"InvalidCredentials"}"#,
        )
        .expect("parse deny");
        assert_eq!(deny.errors.len(), 1);
        assert_eq!(deny.code, "InvalidCredentials");
    }
}
