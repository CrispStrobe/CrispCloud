//! Small bridge only: registry, JSON metadata, and bounded typed byte buffers.
use crisp_smb::{Config, Error, Session};
use flutter_rust_bridge::frb;
use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex, OnceLock,
};

static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
fn sessions() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}
fn session(id: u64) -> anyhow::Result<Arc<Session>> {
    sessions()
        .lock()
        .map_err(|_| Error::new("Internal"))?
        .get(&id)
        .cloned()
        .ok_or_else(|| Error::new("Closed").into())
}
#[frb(sync)]
pub fn create_session(config_json: String) -> anyhow::Result<u64> {
    let config: Config =
        serde_json::from_str(&config_json).map_err(|_| Error::new("InvalidConfig"))?;
    let value = Arc::new(Session::new(config)?);
    let mut registry = sessions().lock().map_err(|_| Error::new("Internal"))?;
    if registry.len() >= 64 {
        return Err(Error::new("TooManySessions").into());
    }
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    registry.insert(id, value);
    Ok(id)
}
pub async fn request(
    id: u64,
    operation: String,
    path: String,
    target: String,
    handle: u64,
) -> anyhow::Result<String> {
    Ok(session(id)?
        .request(&operation, &path, &target, handle)
        .await?
        .to_string())
}
pub async fn read_chunk(id: u64, handle: u64, offset: u64, length: u32) -> anyhow::Result<Vec<u8>> {
    Ok(session(id)?.read_chunk(handle, offset, length).await?)
}
pub async fn write_chunk(id: u64, handle: u64, bytes: Vec<u8>) -> anyhow::Result<()> {
    Ok(session(id)?.write_chunk(handle, bytes).await?)
}
pub async fn download(
    id: u64,
    path: String,
    output: String,
    source: String,
    limit: u64,
) -> anyhow::Result<u64> {
    Ok(session(id)?
        .download(&path, &output, &source, limit)
        .await?)
}
#[frb(sync)]
/// 0 until the running download knows its starting offset, then bytes + 1.
/// The +1 encoding keeps the bridge signature while distinguishing "not
/// started yet" from "starting at byte 0" (see RustSmbSession.download).
pub fn progress(id: u64) -> anyhow::Result<u64> {
    let s = session(id)?;
    Ok(if s.progress_started() { s.progress() + 1 } else { 0 })
}
#[frb(sync)]
pub fn cancel_session(id: u64) -> anyhow::Result<()> {
    session(id)?.cancel();
    Ok(())
}
pub async fn close_session(id: u64) -> anyhow::Result<()> {
    let value = sessions()
        .lock()
        .map_err(|_| Error::new("Internal"))?
        .remove(&id);
    if let Some(value) = value {
        value.close().await;
    }
    Ok(())
}
