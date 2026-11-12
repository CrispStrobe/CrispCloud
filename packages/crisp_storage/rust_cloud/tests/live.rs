//! Live Filen/Internxt round trips through the bridge engine (no Dart).
//!
//! Skips unless credentials are set; never prints them:
//!   CRISP_LIVE_FILEN_EMAIL / CRISP_LIVE_FILEN_PASSWORD
//!   CRISP_LIVE_INTERNXT_EMAIL / CRISP_LIVE_INTERNXT_PASSWORD (test account)
//! Each test works inside one uniquely named scratch folder and trashes it.
use crisp_cloud_bridge::engine::Engine;
use crisp_cloud_bridge::error::ErrorCode;
use crisp_cloud_bridge::session::{Provider, SessionEnvelope};
use crisp_cloud_bridge::transfer::Transfer;
use crisp_cloud_bridge::{api, providers};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

fn credentials(provider: Provider) -> Option<(String, String)> {
    let prefix = match provider {
        Provider::Filen => "CRISP_LIVE_FILEN",
        Provider::Internxt => "CRISP_LIVE_INTERNXT",
    };
    let email = std::env::var(format!("{prefix}_EMAIL")).ok()?;
    let password = std::env::var(format!("{prefix}_PASSWORD")).ok()?;
    (!email.is_empty() && !password.is_empty()).then_some((email, password))
}

fn scratch_name(provider: Provider) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!("/crispcloud-rust-live-{}-{nanos}", provider.as_str())
}

fn round_trip(provider: Provider) {
    let Some((email, password)) = credentials(provider) else {
        eprintln!(
            "skipping {} live test: credentials not set",
            provider.as_str()
        );
        return;
    };
    let envelope = providers::login(provider, &email, &password, None).expect("login");
    let encoded = envelope.encode();
    // Stored envelopes reopen without the password.
    let reopened = SessionEnvelope::decode(&encoded, provider).unwrap();
    let engine = Engine::new(providers::open(&reopened).unwrap());
    let scratch = scratch_name(provider);
    let result =
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| exercise(&engine, &scratch)));
    let cleanup = engine.trash(&scratch);
    if let Err(panic) = result {
        std::panic::resume_unwind(panic);
    }
    cleanup.expect("trash scratch folder");
    assert_eq!(engine.stat(&scratch).unwrap_err().code, ErrorCode::NotFound);
}

fn exercise(engine: &Engine, scratch: &str) {
    let created = engine.mkdir(scratch).unwrap();
    assert!(created.is_dir);
    assert!(engine.list(scratch, true).unwrap().is_empty());

    let dir = tempfile::tempdir().unwrap();
    let data: Vec<u8> = (0..(1024 * 1024 + 4099))
        .map(|i| (i * 13 + 5) as u8)
        .collect();
    let local = dir.path().join("payload.bin");
    std::fs::write(&local, &data).unwrap();
    let upload = Arc::new(Transfer::default());
    assert_eq!(
        engine
            .upload(&local, scratch, "payload.bin", upload.clone())
            .unwrap(),
        data.len() as u64
    );
    assert_eq!(upload.snapshot().1, data.len() as u64);

    let listing = engine.list(scratch, true).unwrap();
    let file = listing
        .iter()
        .find(|e| e.name == "payload.bin")
        .expect("listed");
    assert_eq!(file.size, data.len() as u64);
    assert!(!file.is_dir);

    let out = dir.path().join("out.bin");
    let download = Arc::new(Transfer::default());
    let bytes = engine
        .download(&format!("{scratch}/payload.bin"), &out, download.clone())
        .unwrap();
    assert_eq!(bytes, data.len() as u64);
    assert_eq!(std::fs::read(&out).unwrap(), data);
    assert_eq!(download.snapshot(), (data.len() as u64, data.len() as u64));

    // Cancelled download leaves no partial file behind.
    let cancelled = Arc::new(Transfer::default());
    cancelled.cancel();
    let partial = dir.path().join("partial.bin");
    assert_eq!(
        engine
            .download(&format!("{scratch}/payload.bin"), &partial, cancelled)
            .unwrap_err()
            .code,
        ErrorCode::Cancelled
    );
    assert!(!partial.exists());

    engine.mkdir(&format!("{scratch}/sub/deeper")).unwrap();
    engine
        .rename(&format!("{scratch}/payload.bin"), "renamed.bin")
        .unwrap();
    assert_eq!(
        engine
            .stat(&format!("{scratch}/payload.bin"))
            .unwrap_err()
            .code,
        ErrorCode::NotFound
    );
    engine
        .move_into(&format!("{scratch}/renamed.bin"), &format!("{scratch}/sub"))
        .unwrap();
    let moved = engine.stat(&format!("{scratch}/sub/renamed.bin")).unwrap();
    assert_eq!(moved.size, data.len() as u64);
    engine
        .rename(&format!("{scratch}/sub/deeper"), "deepest")
        .unwrap();
    assert!(
        engine
            .stat(&format!("{scratch}/sub/deepest"))
            .unwrap()
            .is_dir
    );
    engine.trash(&format!("{scratch}/sub/renamed.bin")).unwrap();
    assert_eq!(
        engine
            .stat(&format!("{scratch}/sub/renamed.bin"))
            .unwrap_err()
            .code,
        ErrorCode::NotFound
    );
}

#[test]
fn filen_live_round_trip() {
    round_trip(Provider::Filen);
}

#[test]
fn internxt_live_round_trip() {
    round_trip(Provider::Internxt);
}

#[test]
fn wrong_password_is_auth_failed_without_session() {
    for provider in [Provider::Filen, Provider::Internxt] {
        let Some((email, _)) = credentials(provider) else {
            continue;
        };
        let error = futures::executor::block_on(api::cloud_login(
            provider.as_str().into(),
            email,
            "definitely-not-the-password-1!".into(),
            None,
        ))
        .unwrap_err();
        let value: serde_json::Value = serde_json::from_str(&error.to_string()).unwrap();
        let code = value["code"].as_str().unwrap();
        assert!(
            code == "AuthFailed" || code == "TwoFactorRequired" || code == "RateLimited",
            "{}: {code}",
            provider.as_str()
        );
    }
}
