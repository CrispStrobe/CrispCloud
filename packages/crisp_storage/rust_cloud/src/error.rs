//! Normalized, secret-free errors crossing the Dart boundary.
//!
//! Upstream errors may contain remote paths, account e-mail addresses or raw
//! gateway responses. Only a stable code, a retry hint and (when known) the
//! HTTP status cross the bridge; the Dart side maps them to localized text.
use serde::Serialize;
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum ErrorCode {
    InvalidArgument,
    InvalidPath,
    InvalidName,
    InvalidSession,
    UnsupportedSessionVersion,
    ProviderMismatch,
    AuthFailed,
    TwoFactorRequired,
    SessionExpired,
    NotFound,
    NotAFolder,
    NotAFile,
    AlreadyExists,
    RootMutation,
    Cancelled,
    Closed,
    Busy,
    Network,
    RateLimited,
    Server,
    Io,
    Integrity,
    Provider,
    Internal,
}

impl ErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            ErrorCode::InvalidArgument => "InvalidArgument",
            ErrorCode::InvalidPath => "InvalidPath",
            ErrorCode::InvalidName => "InvalidName",
            ErrorCode::InvalidSession => "InvalidSession",
            ErrorCode::UnsupportedSessionVersion => "UnsupportedSessionVersion",
            ErrorCode::ProviderMismatch => "ProviderMismatch",
            ErrorCode::AuthFailed => "AuthFailed",
            ErrorCode::TwoFactorRequired => "TwoFactorRequired",
            ErrorCode::SessionExpired => "SessionExpired",
            ErrorCode::NotFound => "NotFound",
            ErrorCode::NotAFolder => "NotAFolder",
            ErrorCode::NotAFile => "NotAFile",
            ErrorCode::AlreadyExists => "AlreadyExists",
            ErrorCode::RootMutation => "RootMutation",
            ErrorCode::Cancelled => "Cancelled",
            ErrorCode::Closed => "Closed",
            ErrorCode::Busy => "Busy",
            ErrorCode::Network => "Network",
            ErrorCode::RateLimited => "RateLimited",
            ErrorCode::Server => "Server",
            ErrorCode::Io => "Io",
            ErrorCode::Integrity => "Integrity",
            ErrorCode::Provider => "Provider",
            ErrorCode::Internal => "Internal",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CloudError {
    pub code: ErrorCode,
    pub retryable: bool,
    pub status: Option<u16>,
}

impl CloudError {
    pub fn new(code: ErrorCode) -> Self {
        let retryable = matches!(
            code,
            ErrorCode::Network | ErrorCode::RateLimited | ErrorCode::Server | ErrorCode::Busy
        );
        Self {
            code,
            retryable,
            status: None,
        }
    }

    pub fn with_status(mut self, status: u16) -> Self {
        self.status = Some(status);
        self
    }

    pub fn retryable(mut self, retryable: bool) -> Self {
        self.retryable = retryable;
        self
    }

    pub fn to_json(&self) -> String {
        let mut value = serde_json::json!({
            "code": self.code.as_str(),
            "retryable": self.retryable,
        });
        if let Some(status) = self.status {
            value["status"] = status.into();
        }
        value.to_string()
    }
}

impl fmt::Display for CloudError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.to_json())
    }
}

impl std::error::Error for CloudError {}

pub type CloudResult<T> = Result<T, CloudError>;

/// First three-digit HTTP status after an `HTTP`/`returned` marker.
fn http_status(text: &str) -> Option<u16> {
    for marker in ["http ", "returned ", "status "] {
        let mut rest = text;
        while let Some(index) = rest.find(marker) {
            let after = &rest[index + marker.len()..];
            let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
            if digits.len() == 3 {
                if let Ok(value) = digits.parse::<u16>() {
                    if (100..600).contains(&value) {
                        return Some(value);
                    }
                }
            }
            rest = after;
        }
    }
    None
}

/// Map an upstream error to a normalized code. Pure function of the message
/// and error chain so it is unit-testable; [`crate::engine`] additionally
/// checks the transfer's cancellation token before calling this.
pub fn classify(error: &anyhow::Error) -> CloudError {
    if let Some(found) = error.downcast_ref::<CloudError>() {
        return found.clone();
    }
    for cause in error.chain() {
        if let Some(found) = cause.downcast_ref::<CloudError>() {
            return found.clone();
        }
        if let Some(io) = cause.downcast_ref::<std::io::Error>() {
            if io.to_string().contains(crate::transfer::CANCELLED_MARKER) {
                return CloudError::new(ErrorCode::Cancelled);
            }
        }
    }
    classify_text(&format!("{error:#}"))
}

/// Textual fallback used for upstream `anyhow!` messages.
pub fn classify_text(raw: &str) -> CloudError {
    let text = raw.to_ascii_lowercase();
    let status = http_status(&text);
    let with = |error: CloudError| match status {
        Some(value) => error.with_status(value),
        None => error,
    };
    if text.contains(crate::transfer::CANCELLED_MARKER) || text.contains("transfer cancelled") {
        return CloudError::new(ErrorCode::Cancelled);
    }
    if text.contains("enter_2fa")
        || text.contains("wrong_2fa")
        || text.contains("2fa")
        || text.contains("two factor")
        || text.contains("two-factor")
        || text.contains("tfa")
    {
        return with(CloudError::new(ErrorCode::TwoFactorRequired));
    }
    if text.contains("email_or_password_wrong")
        || text.contains("wrong email or password")
        || text.contains("wrong login credentials")
        || text.contains("invalid credentials")
        || text.contains("decrypting internxt mnemonic")
        || text.contains("auth info failed")
        || text.contains("login failed")
        || text.contains("login access returned")
        || text.contains("login security returned")
    {
        return with(CloudError::new(ErrorCode::AuthFailed));
    }
    if status == Some(401) || text.contains("unauthorized") || text.contains("token expired") {
        return with(CloudError::new(ErrorCode::SessionExpired));
    }
    if status == Some(429) || text.contains("rate limit") || text.contains("too many requests") {
        return with(CloudError::new(ErrorCode::RateLimited));
    }
    if text.contains("not found") || status == Some(404) {
        return with(CloudError::new(ErrorCode::NotFound));
    }
    if status == Some(409) || text.contains("already exists") || text.contains("conflict") {
        return with(CloudError::new(ErrorCode::AlreadyExists));
    }
    if text.contains("hash mismatch")
        || text.contains("integrity")
        || text.contains("aead")
        || text.contains("decrypt")
        || text.contains("authentication tag")
        || text.contains("checksum")
        || text.contains("truncated")
    {
        return with(CloudError::new(ErrorCode::Integrity));
    }
    if let Some(value) = status {
        if value >= 500 {
            return CloudError::new(ErrorCode::Server).with_status(value);
        }
    }
    if text.contains("timed out")
        || text.contains("timeout")
        || text.contains("connection")
        || text.contains("dns")
        || text.contains("error sending request")
        || text.contains("network")
    {
        return with(CloudError::new(ErrorCode::Network));
    }
    if text.contains("no space left") || text.contains("permission denied") || text.contains("os error")
    {
        return with(CloudError::new(ErrorCode::Io));
    }
    with(CloudError::new(ErrorCode::Provider))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_json_contains_only_code_retry_and_status() {
        let json = CloudError::new(ErrorCode::Server).with_status(503).to_json();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["code"], "Server");
        assert_eq!(value["retryable"], true);
        assert_eq!(value["status"], 503);
        assert_eq!(value.as_object().unwrap().len(), 3);
    }

    #[test]
    fn default_retry_hints() {
        assert!(CloudError::new(ErrorCode::Network).retryable);
        assert!(CloudError::new(ErrorCode::RateLimited).retryable);
        assert!(!CloudError::new(ErrorCode::AuthFailed).retryable);
        assert!(!CloudError::new(ErrorCode::Cancelled).retryable);
        assert!(!CloudError::new(ErrorCode::Integrity).retryable);
    }

    #[test]
    fn classifies_filen_login_failures() {
        assert_eq!(
            classify_text("Filen login failed (enter_2fa): Please enter your 2FA code").code,
            ErrorCode::TwoFactorRequired
        );
        assert_eq!(
            classify_text("Filen login failed (wrong_2fa): Invalid").code,
            ErrorCode::TwoFactorRequired
        );
        assert_eq!(
            classify_text("Filen login failed (email_or_password_wrong): Wrong").code,
            ErrorCode::AuthFailed
        );
    }

    #[test]
    fn classifies_internxt_login_failures() {
        assert_eq!(
            classify_text("Internxt login access returned 401 Unauthorized (wrong_2fa): Invalid code").code,
            ErrorCode::TwoFactorRequired
        );
        let error = classify_text("Internxt login access returned 401 Unauthorized: Wrong login credentials");
        assert_eq!(error.code, ErrorCode::AuthFailed);
        assert_eq!(error.status, Some(401));
        assert_eq!(classify_text("decrypting Internxt mnemonic").code, ErrorCode::AuthFailed);
    }

    #[test]
    fn classifies_http_status_families() {
        assert_eq!(classify_text("Filen HTTP 401: nope").code, ErrorCode::SessionExpired);
        let limited = classify_text("Filen HTTP 429: slow down");
        assert_eq!(limited.code, ErrorCode::RateLimited);
        assert!(limited.retryable);
        let server = classify_text("Internxt trash endpoint returned 502 Bad Gateway: x");
        assert_eq!(server.code, ErrorCode::Server);
        assert_eq!(server.status, Some(502));
        assert_eq!(classify_text("Internxt move endpoint returned 409 Conflict: x").code, ErrorCode::AlreadyExists);
        assert_eq!(classify_text("returned 404 Not Found").code, ErrorCode::NotFound);
    }

    #[test]
    fn classifies_paths_integrity_network_and_io() {
        assert_eq!(classify_text("Filen path not found: \"/a\"").code, ErrorCode::NotFound);
        assert_eq!(classify_text("Internxt path component not found: x").code, ErrorCode::NotFound);
        assert_eq!(classify_text("Filen file hash mismatch").code, ErrorCode::Integrity);
        assert_eq!(classify_text("aead::Error").code, ErrorCode::Integrity);
        assert_eq!(classify_text("error sending request for url").code, ErrorCode::Network);
        assert_eq!(classify_text("operation timed out").code, ErrorCode::Network);
        assert_eq!(classify_text("No space left on device (os error 28)").code, ErrorCode::Io);
        assert_eq!(classify_text("something odd").code, ErrorCode::Provider);
    }

    #[test]
    fn classify_prefers_typed_errors_and_cancellation() {
        let typed: anyhow::Error = CloudError::new(ErrorCode::NotAFolder).into();
        assert_eq!(classify(&typed).code, ErrorCode::NotAFolder);
        let wrapped = typed.context("while listing");
        assert_eq!(classify(&wrapped).code, ErrorCode::NotAFolder);
        let io = std::io::Error::other(crate::transfer::CANCELLED_MARKER);
        assert_eq!(classify(&anyhow::Error::new(io)).code, ErrorCode::Cancelled);
        assert_eq!(classify_text("transfer cancelled").code, ErrorCode::Cancelled);
    }

    #[test]
    fn http_status_parser_ignores_non_status_numbers() {
        assert_eq!(http_status("http 503: x"), Some(503));
        assert_eq!(http_status("returned 1234"), None);
        assert_eq!(http_status("chunk 404 of file"), None);
        assert_eq!(http_status("returned 999"), None);
    }
}
