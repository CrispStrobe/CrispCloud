//! Independent SMB engine. No Flutter/Tauri dependency or credential persistence.
#![forbid(unsafe_code)]
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use smb2::{
    ClientConfig, DownloadCheckpoint, FileReader, FileVersion, FileWriter, ReadAhead, SmbClient,
    Tree,
};
use std::io::Write;
use std::{
    collections::HashMap,
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
    time::Duration,
};
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

pub const CHUNK: usize = 256 * 1024;
const MAX_HANDLES: usize = 8;

#[derive(Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub address: String,
    pub share: String,
    pub root: String,
    pub username: String,
    pub password: String,
    #[serde(default)]
    pub domain: String,
    pub require_encryption: bool,
}

/// Stable, credential-free errors across both native consumers.
#[derive(Debug, Serialize)]
pub struct Error {
    pub code: String,
    pub retryable: bool,
}
impl Error {
    pub fn new(code: &str) -> Self {
        Self {
            code: code.into(),
            retryable: false,
        }
    }
}
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", serde_json::to_string(self).unwrap())
    }
}
impl std::error::Error for Error {}
impl From<smb2::Error> for Error {
    fn from(e: smb2::Error) -> Self {
        Self {
            code: format!("{:?}", e.kind()),
            retryable: e.is_retryable(),
        }
    }
}
impl From<std::io::Error> for Error {
    fn from(_: std::io::Error) -> Self {
        Self::new("LocalIo")
    }
}
impl From<serde_json::Error> for Error {
    fn from(_: serde_json::Error) -> Self {
        Self::new("InvalidData")
    }
}
pub type Result<T> = std::result::Result<T, Error>;

pub fn validate_path(path: &str) -> Result<()> {
    if path.starts_with('/')
        || path.contains('\\')
        || path.contains('\0')
        || path.split('/').any(|v| v == "." || v == "..")
    {
        return Err(Error::new("InvalidPath"));
    }
    Ok(())
}

struct Live {
    client: SmbClient,
    tree: Tree,
    readers: HashMap<u64, FileReader>,
    writers: HashMap<u64, FileWriter>,
    next: u64,
}

pub struct Session {
    config: Config,
    live: Mutex<Option<Live>>,
    cancel: CancellationToken,
    progress: AtomicU64,
}
impl Session {
    pub fn new(config: Config) -> Result<Self> {
        validate_path(&config.root)?;
        if config.address.is_empty()
            || config.share.is_empty()
            || config.share.contains(['/', '\\', '\0'])
        {
            return Err(Error::new("InvalidConfig"));
        }
        // Anonymous/guest sessions cannot satisfy our mandatory signing policy.
        if config.username.is_empty() || config.username.eq_ignore_ascii_case("guest") {
            return Err(Error::new("SigningRequired"));
        }
        Ok(Self {
            config,
            live: Mutex::new(None),
            cancel: CancellationToken::new(),
            progress: AtomicU64::new(0),
        })
    }
    pub fn cancel(&self) {
        self.cancel.cancel();
    }
    pub fn progress(&self) -> u64 {
        self.progress.load(Ordering::Relaxed)
    }
    pub async fn close(&self) {
        self.cancel();
        self.live.lock().await.take();
    }
    fn path(&self, path: &str) -> Result<String> {
        validate_path(path)?;
        Ok([
            self.config.root.trim_end_matches('/'),
            path.trim_end_matches('/'),
        ]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("/"))
    }
    async fn connect(&self) -> Result<Live> {
        let c = &self.config;
        let mut client = SmbClient::connect(ClientConfig {
            addr: c.address.clone(),
            username: c.username.clone(),
            password: c.password.clone(),
            domain: c.domain.clone(),
            timeout: Duration::from_secs(15),
            response_timeout: Some(Duration::from_secs(15)),
            require_encryption: c.require_encryption,
            auto_reconnect: false,
            compression: false,
            dfs_enabled: false,
            ..Default::default()
        })
        .await?;
        if !client.session().should_sign {
            return Err(Error::new("SigningRequired"));
        }
        if c.require_encryption && !client.session().should_encrypt {
            return Err(Error::new("EncryptionRequired"));
        }
        client.connection().set_write_budget(4 * CHUNK as u64);
        let tree = client.connect_share(&c.share).await?;
        Ok(Live {
            client,
            tree,
            readers: HashMap::new(),
            writers: HashMap::new(),
            next: 1,
        })
    }
    async fn guarded<T>(&self, work: impl std::future::Future<Output = Result<T>>) -> Result<T> {
        tokio::select! { biased;
            _ = self.cancel.cancelled() => Err(Error::new("Cancelled")),
            result = work => result,
        }
    }
    /// Metadata/mutations use JSON; bulk file bytes use read/write_chunk below.
    pub async fn request(&self, op: &str, path: &str, target: &str, handle: u64) -> Result<Value> {
        let path = self.path(path)?;
        let target = self.path(target)?;
        self.guarded(async {
            let mut guard = self.live.lock().await;
            if guard.is_none() { *guard = Some(self.connect().await?); }
            let live = guard.as_mut().unwrap();
            let Live { client, tree, readers, writers, next } = live;
            match op {
                "list" => {
                    let rows = client.list_directory(tree, &path).await?;
                    if rows.len() > 10000 { return Err(Error::new("FolderTooLarge")); }
                    Ok(Value::Array(rows.into_iter().filter(|e| !e.is_link() && e.name != "." && e.name != "..")
                        .map(|e| json!({"name":e.name,"size":e.size,"directory":e.is_directory})).collect()))
                },
                "stat" => {
                    match client.stat_with_identity(tree, &path).await {
                        Ok((s, identity)) => { if s.is_link() { return Err(Error::new("LinksUnsupported")); }
                            Ok(json!({"size":s.size,"directory":s.is_directory,"modified":s.modified.0,"changed":s.changed.0,"version":normalized_version(FileVersion::new(s.size,s.modified,s.changed,identity))})) },
                        Err(e) if e.kind() == smb2::ErrorKind::NotFound => Ok(Value::Null),
                        Err(e) => Err(e.into()),
                    }
                },
                "openRead" => {
                    if readers.len() + writers.len() >= MAX_HANDLES { return Err(Error::new("TooManyHandles")); }
                    let info = client.stat(tree, &path).await?;
                    if info.is_link() || info.is_directory { return Err(Error::new("InvalidFile")); }
                    let reader = client.open_file_reader(tree, &path).await?;
                    let id = *next; *next += 1;
                    let result = json!({"handle":id,"size":reader.size(),"version":normalized_version(reader.version())});
                    readers.insert(id, reader); Ok(result)
                },
                "closeRead" => { if let Some(reader) = readers.remove(&handle) { reader.close().await?; } Ok(Value::Null) },
                "openWrite" => {
                    if readers.len() + writers.len() >= MAX_HANDLES { return Err(Error::new("TooManyHandles")); }
                    let writer = client.create_file_writer(tree, &path).await?.with_chunk_size(CHUNK as u32);
                    let id = *next; *next += 1; writers.insert(id, writer); Ok(json!(id))
                },
                "finishWrite" => { let writer = writers.remove(&handle).ok_or_else(|| Error::new("InvalidHandle"))?; Ok(json!(writer.finish().await?)) },
                "abortWrite" => { if let Some(writer) = writers.remove(&handle) { writer.abort().await?; } Ok(Value::Null) },
                "mkdir" => { client.create_directory(tree, &path).await?; Ok(Value::Null) },
                "rename" | "delete" | "rmdir" => {
                    if path == self.config.root.trim_end_matches('/') || (op == "rename" && target == self.config.root.trim_end_matches('/')) {
                        return Err(Error::new("RootMutation"));
                    }
                    match op {
                        "rename" => client.rename(tree, &path, &target).await?,
                        "rmdir" => client.delete_directory(tree, &path).await?,
                        _ => client.delete_file(tree, &path).await?,
                    }
                    Ok(Value::Null)
                },
                _ => Err(Error::new("InvalidOperation")),
            }
        }).await
    }
    pub async fn read_chunk(&self, handle: u64, offset: u64, length: u32) -> Result<Vec<u8>> {
        if length as usize > CHUNK {
            return Err(Error::new("TooLarge"));
        }
        self.guarded(async {
            let guard = self.live.lock().await;
            let reader = guard
                .as_ref()
                .and_then(|l| l.readers.get(&handle))
                .ok_or_else(|| Error::new("InvalidHandle"))?;
            Ok(reader.read_at(offset, length as u64).await?)
        })
        .await
    }
    pub async fn write_chunk(&self, handle: u64, data: Vec<u8>) -> Result<()> {
        if data.len() > CHUNK {
            return Err(Error::new("TooLarge"));
        }
        self.guarded(async {
            let mut guard = self.live.lock().await;
            let writer = guard
                .as_mut()
                .and_then(|l| l.writers.get_mut(&handle))
                .ok_or_else(|| Error::new("InvalidHandle"))?;
            writer.write_chunk(&data).await?;
            Ok(())
        })
        .await
    }
    /// Writes only to the caller's staging file. Never publishes a final app file.
    /// Bytes stay native; Dart polls the atomic progress counter.
    pub async fn download(
        &self,
        path: &str,
        output: &str,
        source: &str,
        limit: u64,
    ) -> Result<u64> {
        let path = self.path(path)?;
        self.progress.store(0, Ordering::Relaxed);
        self.guarded(async {
            let mut guard = self.live.lock().await;
            if guard.is_none() {
                *guard = Some(self.connect().await?);
            }
            let Live { client, tree, .. } = guard.as_mut().unwrap();
            let (before, identity) = client.stat_with_identity(tree, &path).await?;
            if before.is_link() || before.is_directory || before.size == 0 || before.size > limit {
                return Err(Error::new("InvalidFile"));
            }
            let version = normalized_version(FileVersion::new(
                before.size,
                before.modified,
                before.changed,
                identity,
            ));
            let marker_path = format!("{output}.resume");
            let saved = read_marker(&marker_path).await;
            let length = tokio::fs::metadata(output)
                .await
                .map(|m| m.len())
                .unwrap_or(0);
            let offset = saved
                .filter(|s| s.source == source && s.validator == version && length <= version.size)
                .map(|_| length)
                .unwrap_or(0);
            let checkpoint = DownloadCheckpoint::new(path.clone(), offset, version);
            // The upstream open rechecks file identity/version before any local truncation.
            let chunk_size = client
                .params()
                .map_or(65536, |p| p.max_read_size)
                .min(CHUNK as u32);
            let mut download = client
                .resume_download(tree, &checkpoint)
                .await?
                .with_chunk_size(chunk_size)
                .with_read_ahead(ReadAhead::Fixed(4));
            // Bounded synchronous writes run on the native worker, not Dart.
            // Cancellation cannot leave an unjoined background write racing resume.
            let mut file = std::fs::OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(offset == 0)
                .append(offset != 0)
                .open(output)?;
            save_marker(
                &marker_path,
                &Marker {
                    source: source.into(),
                    validator: version,
                },
            )
            .await?;
            let mut received = offset;
            self.progress.store(received, Ordering::Relaxed);
            while let Some(chunk) = download.next_chunk().await {
                let bytes = chunk?;
                if bytes.is_empty() || received + bytes.len() as u64 > version.size {
                    return Err(Error::new("InvalidData"));
                }
                file.write_all(&bytes)?;
                received += bytes.len() as u64;
                self.progress.store(received, Ordering::Relaxed);
            }
            file.flush()?;
            if received != version.size {
                return Err(Error::new("Incomplete"));
            }
            let (after, identity) = client.stat_with_identity(tree, &path).await?;
            let after = normalized_version(FileVersion::new(
                after.size,
                after.modified,
                after.changed,
                identity,
            ));
            if version != after {
                return Err(Error::new("FileChanged"));
            }
            Ok(received)
        })
        .await
    }
}
// Servers may return a partial/zero identity. It is not proof of identity;
// normalize it consistently across CREATE and QUERY_INFO, as upstream does.
fn normalized_version(mut version: FileVersion) -> FileVersion {
    version.identity = version
        .identity
        .filter(|id| id.index_number != 0 && id.volume_serial != 0);
    version
}
#[derive(Serialize, Deserialize)]
struct Marker {
    source: String,
    validator: FileVersion,
}
async fn read_marker(path: &str) -> Option<Marker> {
    if tokio::fs::metadata(path).await.ok()?.len() > 8192 {
        return None;
    }
    serde_json::from_slice(&tokio::fs::read(path).await.ok()?).ok()
}
async fn save_marker(path: &str, marker: &Marker) -> Result<()> {
    let temporary = format!("{path}.tmp");
    tokio::fs::write(&temporary, serde_json::to_vec(marker)?).await?;
    // Replacement semantics differ on Windows; old marker is disposable only.
    if Path::new(path).exists() {
        tokio::fs::remove_file(path).await?;
    }
    tokio::fs::rename(temporary, path).await?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn paths_are_confined() {
        for p in ["../secret", "/absolute", "a/../b", "a\\b", "x\0"] {
            assert!(validate_path(p).is_err());
        }
        for p in ["", "a/Chapter #1.mp3", "literal%2Fname"] {
            assert!(validate_path(p).is_ok());
        }
    }
    #[test]
    fn credentials_are_not_in_errors() {
        assert_eq!(
            Error::new("AuthRequired").to_string(),
            r#"{"code":"AuthRequired","retryable":false}"#
        );
    }
    fn config() -> Config {
        Config {
            address: "127.0.0.1:1".into(),
            share: "books".into(),
            root: "audio".into(),
            username: "reader".into(),
            password: "private-password".into(),
            domain: "".into(),
            require_encryption: true,
        }
    }
    #[test]
    fn rejects_unsigned_accounts_and_invalid_roots_before_connecting() {
        for name in ["", "guest", "GUEST"] {
            let mut cfg = config();
            cfg.username = name.into();
            assert_eq!(Session::new(cfg).err().unwrap().code, "SigningRequired");
        }
        for root in ["../secret", "a/../b", "/absolute", "a\\b"] {
            let mut cfg = config();
            cfg.root = root.into();
            assert_eq!(Session::new(cfg).err().unwrap().code, "InvalidPath");
        }
        let mut cfg = config();
        cfg.share = "other/share".into();
        assert_eq!(Session::new(cfg).err().unwrap().code, "InvalidConfig");
    }
    #[test]
    fn path_resolution_retains_configured_root() {
        let session = Session::new(config()).unwrap();
        assert_eq!(session.path("").unwrap(), "audio");
        assert_eq!(
            session.path("Chapter #1.mp3").unwrap(),
            "audio/Chapter #1.mp3"
        );
        assert!(session.path("../escape").is_err());
    }
    #[test]
    fn upstream_auth_details_are_redacted() {
        let error = Error::from(smb2::Error::Auth {
            message: "private-password server/path".into(),
        });
        assert!(!error.to_string().contains("private-password"));
        assert!(!error.to_string().contains("server/path"));
        assert!(!error.retryable);
    }
    #[test]
    fn encryption_policy_is_required_in_core_configuration() {
        let missing =
            r#"{"address":"host:445","share":"books","root":"","username":"u","password":"p"}"#;
        assert!(serde_json::from_str::<Config>(missing).is_err());
        let unknown = missing.replace("{", r#"{"unexpected":true,"require_encryption":true,"#);
        assert!(serde_json::from_str::<Config>(&unknown).is_err());
    }
    #[tokio::test]
    async fn cancellation_and_transfer_bounds_do_not_need_a_connection() {
        let session = Session::new(config()).unwrap();
        assert_eq!(
            session
                .read_chunk(1, 0, CHUNK as u32 + 1)
                .await
                .unwrap_err()
                .code,
            "TooLarge"
        );
        assert_eq!(
            session
                .write_chunk(1, vec![0; CHUNK + 1])
                .await
                .unwrap_err()
                .code,
            "TooLarge"
        );
        session.cancel();
        assert_eq!(
            session.request("list", "", "", 0).await.unwrap_err().code,
            "Cancelled"
        );
        session.close().await;
        session.close().await;
    }
    #[tokio::test]
    async fn resume_markers_reject_foreign_malformed_and_oversized_data() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("partial.resume");
        let name = path.to_str().unwrap();
        for bytes in [
            br#"{"source":"smb://host/books/a","validator":"libsmb2"}"#.to_vec(),
            b"not json".to_vec(),
            vec![b'x'; 8193],
        ] {
            tokio::fs::write(&path, bytes).await.unwrap();
            assert!(read_marker(name).await.is_none());
        }
        let version: FileVersion = serde_json::from_value(json!({"size":42,"modified":1,"changed":2,"identity":null})).unwrap();
        save_marker(
            name,
            &Marker {
                source: "smb://host/books/a".into(),
                validator: version,
            },
        )
        .await
        .unwrap();
        let loaded = read_marker(name).await.unwrap();
        assert_eq!(loaded.validator, version);
        assert_eq!(loaded.source, "smb://host/books/a");
    }
}
