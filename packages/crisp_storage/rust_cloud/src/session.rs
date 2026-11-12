//! Versioned Rust session envelope.
//!
//! Dart and Rust session JSON are deliberately not interchangeable: the host
//! stores this envelope as an opaque secret and must reconnect (fresh login)
//! when the format, version or provider does not match.
use crate::error::{CloudError, CloudResult, ErrorCode};
use serde::{Deserialize, Serialize};

pub const SESSION_FORMAT: &str = "crisp-cloud-rust-session";
pub const SESSION_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Filen,
    Internxt,
}

impl Provider {
    pub fn parse(value: &str) -> CloudResult<Self> {
        match value {
            "filen" => Ok(Provider::Filen),
            "internxt" => Ok(Provider::Internxt),
            _ => Err(CloudError::new(ErrorCode::InvalidArgument)),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Provider::Filen => "filen",
            Provider::Internxt => "internxt",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionEnvelope {
    pub format: String,
    pub version: u32,
    pub provider: Provider,
    /// Account e-mail, kept outside the inner session for identity checks.
    pub account: String,
    pub session: serde_json::Value,
}

impl SessionEnvelope {
    pub fn new(provider: Provider, account: &str, session: serde_json::Value) -> Self {
        Self {
            format: SESSION_FORMAT.into(),
            version: SESSION_VERSION,
            provider,
            account: account.into(),
            session,
        }
    }

    pub fn encode(&self) -> String {
        serde_json::to_string(self).expect("session envelope is always serializable")
    }

    /// Decode and validate an envelope for `expected`. Unknown formats (for
    /// example a Dart credential map) are rejected, never reinterpreted.
    pub fn decode(raw: &str, expected: Provider) -> CloudResult<Self> {
        let value: serde_json::Value =
            serde_json::from_str(raw).map_err(|_| CloudError::new(ErrorCode::InvalidSession))?;
        if value.get("format").and_then(|v| v.as_str()) != Some(SESSION_FORMAT) {
            return Err(CloudError::new(ErrorCode::InvalidSession));
        }
        match value.get("version").and_then(|v| v.as_u64()) {
            Some(version) if version == u64::from(SESSION_VERSION) => {}
            Some(_) => return Err(CloudError::new(ErrorCode::UnsupportedSessionVersion)),
            None => return Err(CloudError::new(ErrorCode::InvalidSession)),
        }
        let envelope: SessionEnvelope =
            serde_json::from_value(value).map_err(|_| CloudError::new(ErrorCode::InvalidSession))?;
        if envelope.provider != expected {
            return Err(CloudError::new(ErrorCode::ProviderMismatch));
        }
        if !envelope.session.is_object() {
            return Err(CloudError::new(ErrorCode::InvalidSession));
        }
        Ok(envelope)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> SessionEnvelope {
        SessionEnvelope::new(Provider::Filen, "a@example.com", serde_json::json!({"k": 1}))
    }

    #[test]
    fn round_trips() {
        let encoded = sample().encode();
        assert_eq!(SessionEnvelope::decode(&encoded, Provider::Filen).unwrap(), sample());
    }

    #[test]
    fn provider_names_parse_strictly() {
        assert_eq!(Provider::parse("filen").unwrap(), Provider::Filen);
        assert_eq!(Provider::parse("internxt").unwrap(), Provider::Internxt);
        assert_eq!(Provider::parse("Filen").unwrap_err().code, ErrorCode::InvalidArgument);
        assert_eq!(Provider::parse("").unwrap_err().code, ErrorCode::InvalidArgument);
        assert_eq!(Provider::Internxt.as_str(), "internxt");
    }

    #[test]
    fn rejects_other_provider() {
        let encoded = sample().encode();
        assert_eq!(
            SessionEnvelope::decode(&encoded, Provider::Internxt).unwrap_err().code,
            ErrorCode::ProviderMismatch
        );
    }

    #[test]
    fn rejects_future_and_missing_versions() {
        let mut value: serde_json::Value = serde_json::from_str(&sample().encode()).unwrap();
        value["version"] = 2.into();
        assert_eq!(
            SessionEnvelope::decode(&value.to_string(), Provider::Filen).unwrap_err().code,
            ErrorCode::UnsupportedSessionVersion
        );
        value.as_object_mut().unwrap().remove("version");
        assert_eq!(
            SessionEnvelope::decode(&value.to_string(), Provider::Filen).unwrap_err().code,
            ErrorCode::InvalidSession
        );
    }

    #[test]
    fn rejects_dart_credential_maps_and_garbage() {
        for raw in [
            r#"{"email":"a","apiKey":"k","masterKeys":"m"}"#,
            r#"{"token":"t","mnemonic":"m"}"#,
            "not json",
            "[]",
            r#"{"format":"crisp-cloud-rust-session","version":1,"provider":"filen","account":"a","session":"str"}"#,
            r#"{"format":"crisp-cloud-rust-session","version":1,"provider":"dropbox","account":"a","session":{}}"#,
        ] {
            let error = SessionEnvelope::decode(raw, Provider::Filen).unwrap_err();
            assert_eq!(error.code, ErrorCode::InvalidSession, "{raw}");
        }
    }
}
