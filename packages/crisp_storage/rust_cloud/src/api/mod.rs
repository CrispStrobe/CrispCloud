//! flutter_rust_bridge surface for the Filen/Internxt Rust engines.
//!
//! Keep this layer thin: session/transfer registries, JSON metadata and
//! normalized errors. All network work runs in [`crate::worker`]. Errors are
//! `anyhow` values whose message is the secret-free JSON from
//! [`crate::error::CloudError`].
use crate::engine::Engine;
use crate::error::{CloudError, CloudResult, ErrorCode};
use crate::session::{Provider, SessionEnvelope, SESSION_VERSION};
use crate::{providers, transfer, worker};
use flutter_rust_bridge::frb;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

pub const MAX_SESSIONS: usize = 64;
static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Engine>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);

fn sessions() -> &'static Mutex<HashMap<u64, Arc<Engine>>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn engine(id: u64) -> CloudResult<Arc<Engine>> {
    sessions()
        .lock()
        .map_err(|_| CloudError::new(ErrorCode::Internal))?
        .get(&id)
        .cloned()
        .ok_or_else(|| CloudError::new(ErrorCode::Closed))
}

fn out<T>(result: CloudResult<T>) -> anyhow::Result<T> {
    result.map_err(|error| anyhow::anyhow!(error.to_json()))
}

/// Cheap probe used by Dart to verify the native library before any
/// credentials are passed. Never touches the network.
#[frb(sync)]
pub fn cloud_bridge_info() -> String {
    serde_json::json!({
        "bridge": env!("CARGO_PKG_VERSION"),
        "session_version": SESSION_VERSION,
        "providers": ["filen", "internxt"],
        "max_sessions": MAX_SESSIONS,
        "max_workers": worker::MAX_WORKERS,
    })
    .to_string()
}

/// Authenticate and return a versioned session envelope (an opaque secret
/// for the host's secure store). Does not register a session.
pub async fn cloud_login(
    provider: String,
    email: String,
    password: String,
    two_factor_code: Option<String>,
) -> anyhow::Result<String> {
    out(login_impl(provider, email, password, two_factor_code).await)
}

async fn login_impl(
    provider: String,
    email: String,
    password: String,
    two_factor_code: Option<String>,
) -> CloudResult<String> {
    let provider = Provider::parse(&provider)?;
    worker::run(move || {
        providers::login(provider, &email, &password, two_factor_code.as_deref())
            .map(|envelope| envelope.encode())
            .map_err(|error| crate::error::classify(&error))
    })
    .await
}

/// Validate a stored envelope and register a session. No network access.
pub async fn cloud_open_session(provider: String, session_json: String) -> anyhow::Result<u64> {
    out(open_impl(&provider, &session_json))
}

pub(crate) fn open_impl(provider: &str, session_json: &str) -> CloudResult<u64> {
    let provider = Provider::parse(provider)?;
    let envelope = SessionEnvelope::decode(session_json, provider)?;
    let backend = providers::open(&envelope)?;
    register(Engine::new(backend))
}

pub(crate) fn register(engine: Engine) -> CloudResult<u64> {
    let mut registry = sessions()
        .lock()
        .map_err(|_| CloudError::new(ErrorCode::Internal))?;
    if registry.len() >= MAX_SESSIONS {
        return Err(CloudError::new(ErrorCode::Busy));
    }
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    registry.insert(id, Arc::new(engine));
    Ok(id)
}

/// `{provider, account, root, revision}`; contains no secrets.
#[frb(sync)]
pub fn cloud_session_info(id: u64) -> anyhow::Result<String> {
    out(engine(id).map(|engine| engine.info().to_string()))
}

/// Increments when the provider renewed its tokens; persist a fresh
/// [`cloud_export_session`] when it changes.
#[frb(sync)]
pub fn cloud_session_revision(id: u64) -> anyhow::Result<u64> {
    out(engine(id).map(|engine| engine.revision()))
}

pub async fn cloud_export_session(id: u64) -> anyhow::Result<String> {
    out(export_impl(id))
}

pub(crate) fn export_impl(id: u64) -> CloudResult<String> {
    let engine = engine(id)?;
    let info = engine.info();
    let session = engine.export_session()?;
    Ok(SessionEnvelope::new(
        engine.provider(),
        info["account"].as_str().unwrap_or_default(),
        session,
    )
    .encode())
}

pub async fn cloud_list(id: u64, path: String, fresh: bool) -> anyhow::Result<String> {
    out(on_worker(id, move |engine| {
        let items = engine.list(&path, fresh)?;
        Ok(serde_json::Value::Array(items.iter().map(|e| e.to_json()).collect()).to_string())
    })
    .await)
}

pub async fn cloud_stat(id: u64, path: String) -> anyhow::Result<String> {
    out(on_worker(id, move |engine| {
        Ok(engine.stat(&path)?.to_json().to_string())
    })
    .await)
}

pub async fn cloud_mkdir(id: u64, path: String) -> anyhow::Result<String> {
    out(on_worker(id, move |engine| {
        Ok(engine.mkdir(&path)?.to_json().to_string())
    })
    .await)
}

pub async fn cloud_rename(id: u64, path: String, new_name: String) -> anyhow::Result<()> {
    out(on_worker(id, move |engine| engine.rename(&path, &new_name)).await)
}

pub async fn cloud_move(id: u64, path: String, target_folder: String) -> anyhow::Result<()> {
    out(on_worker(id, move |engine| engine.move_into(&path, &target_folder)).await)
}

pub async fn cloud_trash(id: u64, path: String) -> anyhow::Result<()> {
    out(on_worker(id, move |engine| engine.trash(&path)).await)
}

pub async fn cloud_upload(
    id: u64,
    transfer: u64,
    local_path: String,
    target_folder: String,
    name: String,
) -> anyhow::Result<u64> {
    out(async move {
        let handle = transfer::registry().get(transfer)?;
        on_worker(id, move |engine| {
            engine.upload(&PathBuf::from(local_path), &target_folder, &name, handle)
        })
        .await
    }
    .await)
}

pub async fn cloud_download(
    id: u64,
    transfer: u64,
    remote_path: String,
    local_path: String,
) -> anyhow::Result<u64> {
    out(async move {
        let handle = transfer::registry().get(transfer)?;
        on_worker(id, move |engine| {
            engine.download(&remote_path, &PathBuf::from(local_path), handle)
        })
        .await
    }
    .await)
}

async fn on_worker<T, F>(id: u64, job: F) -> CloudResult<T>
where
    T: Send + 'static,
    F: FnOnce(&Engine) -> CloudResult<T> + Send + 'static,
{
    let engine = engine(id)?;
    worker::run(move || job(&engine)).await
}

#[frb(sync)]
pub fn cloud_new_transfer() -> anyhow::Result<u64> {
    out(transfer::registry().create())
}

/// `[completed_bytes, total_bytes]`.
#[frb(sync)]
pub fn cloud_transfer_progress(transfer: u64) -> anyhow::Result<Vec<u64>> {
    out(transfer::registry().get(transfer).map(|t| {
        let (done, total) = t.snapshot();
        vec![done, total]
    }))
}

#[frb(sync)]
pub fn cloud_cancel_transfer(transfer: u64) -> anyhow::Result<()> {
    out(transfer::registry().get(transfer).map(|t| t.cancel()))
}

#[frb(sync)]
pub fn cloud_release_transfer(transfer: u64) -> anyhow::Result<()> {
    out(transfer::registry().release(transfer))
}

/// Unregister a session. In-flight worker calls keep their own reference and
/// finish; later calls with this id fail with `Closed`.
#[frb(sync)]
pub fn cloud_close_session(id: u64) -> anyhow::Result<()> {
    out(sessions()
        .lock()
        .map_err(|_| CloudError::new(ErrorCode::Internal))
        .map(|mut registry| {
            registry.remove(&id);
        }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::fake::FakeBackend;
    use crate::providers::tests::{filen_envelope, internxt_envelope};
    use futures::executor::block_on;

    fn code(error: anyhow::Error) -> String {
        let value: serde_json::Value = serde_json::from_str(&error.to_string()).unwrap();
        value["code"].as_str().unwrap().to_owned()
    }

    #[test]
    fn bridge_info_is_json_without_secrets() {
        let info: serde_json::Value = serde_json::from_str(&cloud_bridge_info()).unwrap();
        assert_eq!(info["session_version"], 1);
        assert_eq!(info["providers"][1], "internxt");
    }

    #[test]
    fn open_info_export_close_round_trip_for_both_providers() {
        for (provider, envelope, root) in [
            ("filen", filen_envelope(), "root-f"),
            ("internxt", internxt_envelope(), "root-i"),
        ] {
            let id = block_on(cloud_open_session(provider.into(), envelope.encode())).unwrap();
            let info: serde_json::Value =
                serde_json::from_str(&cloud_session_info(id).unwrap()).unwrap();
            assert_eq!(info["provider"], provider);
            assert_eq!(info["root"], root);
            assert_eq!(cloud_session_revision(id).unwrap(), 1);
            let exported = block_on(cloud_export_session(id)).unwrap();
            let decoded =
                SessionEnvelope::decode(&exported, Provider::parse(provider).unwrap()).unwrap();
            assert_eq!(decoded, envelope);
            cloud_close_session(id).unwrap();
            assert_eq!(code(cloud_session_info(id).unwrap_err()), "Closed");
            assert_eq!(
                code(block_on(cloud_list(id, "/".into(), false)).unwrap_err()),
                "Closed"
            );
            cloud_close_session(id).unwrap();
        }
    }

    #[test]
    fn open_rejects_wrong_provider_dart_maps_and_unknown_provider() {
        let filen = filen_envelope().encode();
        assert_eq!(
            code(block_on(cloud_open_session("internxt".into(), filen.clone())).unwrap_err()),
            "ProviderMismatch"
        );
        assert_eq!(
            code(
                block_on(cloud_open_session(
                    "filen".into(),
                    r#"{"apiKey":"k"}"#.into()
                ))
                .unwrap_err()
            ),
            "InvalidSession"
        );
        assert_eq!(
            code(block_on(cloud_open_session("dropbox".into(), filen)).unwrap_err()),
            "InvalidArgument"
        );
    }

    #[test]
    fn login_validates_provider_and_arguments_before_network() {
        assert_eq!(
            code(block_on(cloud_login("box".into(), "a".into(), "b".into(), None)).unwrap_err()),
            "InvalidArgument"
        );
        assert_eq!(
            code(block_on(cloud_login("filen".into(), "".into(), "b".into(), None)).unwrap_err()),
            "InvalidArgument"
        );
    }

    #[test]
    fn engine_operations_through_the_bridge_with_a_fake_backend() {
        let (backend, _) = FakeBackend::new();
        let id = register(Engine::new(Box::new(backend))).unwrap();
        let created: serde_json::Value =
            serde_json::from_str(&block_on(cloud_mkdir(id, "/a/b".into())).unwrap()).unwrap();
        assert_eq!(created["name"], "b");
        assert_eq!(created["directory"], true);
        let listing: serde_json::Value =
            serde_json::from_str(&block_on(cloud_list(id, "/a".into(), true)).unwrap()).unwrap();
        assert_eq!(listing.as_array().unwrap().len(), 1);
        block_on(cloud_rename(id, "/a/b".into(), "c".into())).unwrap();
        block_on(cloud_mkdir(id, "/z".into())).unwrap();
        block_on(cloud_move(id, "/a/c".into(), "/z".into())).unwrap();
        let stat: serde_json::Value =
            serde_json::from_str(&block_on(cloud_stat(id, "/z/c".into())).unwrap()).unwrap();
        assert_eq!(stat["name"], "c");
        block_on(cloud_trash(id, "/z/c".into())).unwrap();
        assert_eq!(
            code(block_on(cloud_stat(id, "/z/c".into())).unwrap_err()),
            "NotFound"
        );
        assert_eq!(
            code(block_on(cloud_trash(id, "/".into())).unwrap_err()),
            "RootMutation"
        );
        cloud_close_session(id).unwrap();
    }

    #[test]
    fn transfers_through_the_bridge_with_progress_and_cancel() {
        let (backend, _) = FakeBackend::new();
        let id = register(Engine::new(Box::new(backend))).unwrap();
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("s.bin");
        std::fs::write(&source, vec![9u8; 4096]).unwrap();
        let up = cloud_new_transfer().unwrap();
        let sent = block_on(cloud_upload(
            id,
            up,
            source.to_string_lossy().into(),
            "/".into(),
            "s.bin".into(),
        ))
        .unwrap();
        assert_eq!(sent, 4096);
        assert_eq!(cloud_transfer_progress(up).unwrap(), vec![4096, 4096]);
        cloud_release_transfer(up).unwrap();
        assert_eq!(code(cloud_transfer_progress(up).unwrap_err()), "Closed");

        let down = cloud_new_transfer().unwrap();
        let target = dir.path().join("t.bin");
        block_on(cloud_download(
            id,
            down,
            "/s.bin".into(),
            target.to_string_lossy().into(),
        ))
        .unwrap();
        assert_eq!(std::fs::read(&target).unwrap().len(), 4096);
        cloud_release_transfer(down).unwrap();

        let cancelled = cloud_new_transfer().unwrap();
        cloud_cancel_transfer(cancelled).unwrap();
        let other = dir.path().join("u.bin");
        assert_eq!(
            code(
                block_on(cloud_download(
                    id,
                    cancelled,
                    "/s.bin".into(),
                    other.to_string_lossy().into()
                ))
                .unwrap_err()
            ),
            "Cancelled"
        );
        assert!(!other.exists());
        cloud_release_transfer(cancelled).unwrap();
        assert_eq!(
            code(block_on(cloud_download(id, cancelled, "/s.bin".into(), "x".into())).unwrap_err()),
            "Closed"
        );
        cloud_close_session(id).unwrap();
    }
}
