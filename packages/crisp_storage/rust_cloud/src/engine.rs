//! Provider-neutral engine: path resolution, validation and local staging
//! around a small [`Backend`] trait implemented by Filen and Internxt.
//!
//! Every method here is blocking and must run on a dedicated storage worker
//! (see [`crate::worker`]), never on the Flutter UI thread or inside a Tokio
//! task: both upstream clients use `reqwest::blocking`.
use crate::error::{classify, CloudError, CloudResult, ErrorCode};
use crate::paths;
use crate::session::Provider;
use crate::transfer::{CountingReader, CountingWriter, Transfer};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Provider-native identity needed by follow-up operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Native {
    None,
    Filen(Box<crisp_filen::NativeItem>),
    Internxt(Box<crisp_internxt::NativeItem>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub uuid: String,
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    /// Milliseconds since the Unix epoch when the provider reports it.
    pub modified_ms: Option<i64>,
    pub mime: Option<String>,
    pub native: Native,
}

impl Entry {
    pub fn folder(uuid: &str, name: &str) -> Self {
        Self {
            uuid: uuid.into(),
            name: name.into(),
            is_dir: true,
            size: 0,
            modified_ms: None,
            mime: None,
            native: Native::None,
        }
    }

    pub fn to_json(&self) -> serde_json::Value {
        let mut value = serde_json::json!({
            "uuid": self.uuid,
            "name": self.name,
            "directory": self.is_dir,
            "size": self.size,
        });
        if let Some(modified) = self.modified_ms {
            value["modified"] = modified.into();
        }
        if let Some(mime) = &self.mime {
            value["mime"] = mime.clone().into();
        }
        value
    }
}

pub type Progress<'a> = &'a Transfer;

pub trait Backend: Send + Sync {
    fn provider(&self) -> Provider;
    fn account(&self) -> String;
    fn root(&self) -> Entry;
    fn list(&self, folder: &Entry, fresh: bool) -> anyhow::Result<Vec<Entry>>;
    fn create_folder(&self, parent: &Entry, name: &str) -> anyhow::Result<Entry>;
    fn rename(&self, item: &Entry, new_name: &str) -> anyhow::Result<()>;
    fn move_to(&self, item: &Entry, folder: &Entry) -> anyhow::Result<()>;
    fn trash(&self, item: &Entry) -> anyhow::Result<()>;
    /// Upload `size` bytes from `reader` as `name` inside `parent`.
    fn upload(
        &self,
        parent: &Entry,
        name: &str,
        size: u64,
        reader: &mut dyn std::io::Read,
    ) -> anyhow::Result<()>;
    fn download(&self, item: &Entry, writer: &mut dyn Write) -> anyhow::Result<u64>;
    /// Current provider session as JSON (it can change after token renewal).
    fn export_session(&self) -> anyhow::Result<serde_json::Value>;
    /// Incremented whenever [`Backend::export_session`] would change.
    fn revision(&self) -> u64;
}

/// How long a local mutation stays visible over the provider's listing.
/// Internxt's listing lags behind its writes for a few hundred milliseconds,
/// so a folder created a moment ago may be missing and a trashed item may
/// still appear. Entries leave the overlay as soon as the listing agrees.
const OVERLAY_TTL: Duration = Duration::from_secs(30);

/// Read-your-writes overlay: folder uuid -> pending changes.
#[derive(Default)]
struct Overlay {
    added: HashMap<String, Vec<(Entry, Instant)>>,
    /// (uuid, name) pairs that must not be listed; `None` hides any name.
    hidden: HashMap<String, Vec<(String, Option<String>, Instant)>>,
}

impl Overlay {
    fn add(&mut self, parent: &str, entry: Entry) {
        let list = self.added.entry(parent.to_owned()).or_default();
        list.retain(|(e, _)| e.uuid != entry.uuid);
        list.push((entry, Instant::now()));
    }

    fn hide(&mut self, parent: &str, uuid: &str, name: Option<&str>) {
        if let Some(list) = self.added.get_mut(parent) {
            list.retain(|(e, _)| e.uuid != uuid);
        }
        self.hidden.entry(parent.to_owned()).or_default().push((
            uuid.to_owned(),
            name.map(str::to_owned),
            Instant::now(),
        ));
    }

    fn apply(&mut self, parent: &str, mut items: Vec<Entry>) -> Vec<Entry> {
        let now = Instant::now();
        if let Some(hidden) = self.hidden.get_mut(parent) {
            hidden.retain(|(uuid, name, at)| {
                now.duration_since(*at) < OVERLAY_TTL
                    && items.iter().any(|item| {
                        &item.uuid == uuid && name.as_ref().is_none_or(|n| &item.name == n)
                    })
            });
            items.retain(|item| {
                !hidden.iter().any(|(uuid, name, _)| {
                    &item.uuid == uuid && name.as_ref().is_none_or(|n| &item.name == n)
                })
            });
        }
        if let Some(added) = self.added.get_mut(parent) {
            added.retain(|(entry, at)| {
                now.duration_since(*at) < OVERLAY_TTL
                    && !items
                        .iter()
                        .any(|item| item.uuid == entry.uuid && item.name == entry.name)
            });
            for (entry, _) in added.iter() {
                items.retain(|item| item.uuid != entry.uuid);
                items.push(entry.clone());
            }
        }
        items
    }
}

pub struct Engine {
    backend: Box<dyn Backend>,
    overlay: Mutex<Overlay>,
}

static STAGING_COUNTER: AtomicU64 = AtomicU64::new(0);

fn fail(error: anyhow::Error, transfer: Option<&Transfer>) -> CloudError {
    if transfer.is_some_and(Transfer::is_cancelled) {
        return CloudError::new(ErrorCode::Cancelled);
    }
    classify(&error)
}

impl Engine {
    pub fn new(backend: Box<dyn Backend>) -> Self {
        Self {
            backend,
            overlay: Mutex::new(Overlay::default()),
        }
    }

    pub fn provider(&self) -> Provider {
        self.backend.provider()
    }

    pub fn info(&self) -> serde_json::Value {
        serde_json::json!({
            "provider": self.backend.provider().as_str(),
            "account": self.backend.account(),
            "root": self.backend.root().uuid,
            "revision": self.backend.revision(),
        })
    }

    pub fn revision(&self) -> u64 {
        self.backend.revision()
    }

    pub fn export_session(&self) -> CloudResult<serde_json::Value> {
        self.backend.export_session().map_err(|e| fail(e, None))
    }

    fn overlay(&self) -> std::sync::MutexGuard<'_, Overlay> {
        self.overlay.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Provider listing with this engine's own recent mutations applied.
    fn listing(&self, folder: &Entry, fresh: bool) -> CloudResult<Vec<Entry>> {
        let items = self
            .backend
            .list(folder, fresh)
            .map_err(|e| fail(e, None))?;
        Ok(self.overlay().apply(&folder.uuid, items))
    }

    fn child(&self, folder: &Entry, name: &str, fresh: bool) -> CloudResult<Option<Entry>> {
        Ok(self
            .listing(folder, fresh)?
            .into_iter()
            .find(|item| item.name == name))
    }

    fn resolve_parts(&self, parts: &[String], fresh: bool) -> CloudResult<Entry> {
        let mut current = self.backend.root();
        for part in parts {
            if !current.is_dir {
                return Err(CloudError::new(ErrorCode::NotAFolder));
            }
            current = self
                .child(&current, part, fresh)?
                .ok_or_else(|| CloudError::new(ErrorCode::NotFound))?;
        }
        Ok(current)
    }

    pub fn stat(&self, path: &str) -> CloudResult<Entry> {
        self.resolve_parts(&paths::components(path)?, false)
    }

    fn folder(&self, path: &str, fresh: bool) -> CloudResult<Entry> {
        let entry = self.resolve_parts(&paths::components(path)?, fresh)?;
        if !entry.is_dir {
            return Err(CloudError::new(ErrorCode::NotAFolder));
        }
        Ok(entry)
    }

    pub fn list(&self, path: &str, fresh: bool) -> CloudResult<Vec<Entry>> {
        let folder = self.folder(path, fresh)?;
        self.listing(&folder, fresh)
    }

    /// Create every missing folder in `path`; existing folders are reused.
    pub fn mkdir(&self, path: &str) -> CloudResult<Entry> {
        let parts = paths::components(path)?;
        let mut current = self.backend.root();
        for part in &parts {
            paths::validate_name(part)?;
            current = match self.child(&current, part, false)? {
                Some(existing) if existing.is_dir => existing,
                Some(_) => return Err(CloudError::new(ErrorCode::AlreadyExists)),
                None => {
                    let created = self
                        .backend
                        .create_folder(&current, part)
                        .map_err(|e| fail(e, None))?;
                    self.overlay().add(&current.uuid, created.clone());
                    created
                }
            };
        }
        Ok(current)
    }

    pub fn rename(&self, path: &str, new_name: &str) -> CloudResult<()> {
        paths::validate_name(new_name)?;
        let parts = paths::components(path)?;
        if parts.is_empty() {
            return Err(CloudError::new(ErrorCode::RootMutation));
        }
        let item = self.resolve_parts(&parts, false)?;
        if item.name == new_name {
            return Ok(());
        }
        let parent = self.resolve_parts(&parts[..parts.len() - 1], false)?;
        if self.child(&parent, new_name, false)?.is_some() {
            return Err(CloudError::new(ErrorCode::AlreadyExists));
        }
        self.backend
            .rename(&item, new_name)
            .map_err(|e| fail(e, None))?;
        let mut overlay = self.overlay();
        overlay.hide(&parent.uuid, &item.uuid, Some(&item.name));
        overlay.add(
            &parent.uuid,
            Entry {
                name: new_name.to_owned(),
                ..item
            },
        );
        Ok(())
    }

    /// Move `path` into the existing folder `target_folder`.
    pub fn move_into(&self, path: &str, target_folder: &str) -> CloudResult<()> {
        let source = paths::components(path)?;
        let target = paths::components(target_folder)?;
        if source.is_empty() {
            return Err(CloudError::new(ErrorCode::RootMutation));
        }
        if paths::is_same_or_descendant(&target, &source) {
            return Err(CloudError::new(ErrorCode::InvalidPath));
        }
        let item = self.resolve_parts(&source, false)?;
        let parent = self.resolve_parts(&source[..source.len() - 1], false)?;
        if target == source[..source.len() - 1] {
            return Ok(());
        }
        let folder = self.resolve_parts(&target, false)?;
        if !folder.is_dir {
            return Err(CloudError::new(ErrorCode::NotAFolder));
        }
        if self.child(&folder, &item.name, false)?.is_some() {
            return Err(CloudError::new(ErrorCode::AlreadyExists));
        }
        self.backend
            .move_to(&item, &folder)
            .map_err(|e| fail(e, None))?;
        let mut overlay = self.overlay();
        overlay.hide(&parent.uuid, &item.uuid, None);
        overlay.add(&folder.uuid, item);
        Ok(())
    }

    pub fn trash(&self, path: &str) -> CloudResult<()> {
        let parts = paths::components(path)?;
        if parts.is_empty() {
            return Err(CloudError::new(ErrorCode::RootMutation));
        }
        let item = self.resolve_parts(&parts, false)?;
        let parent = self.resolve_parts(&parts[..parts.len() - 1], false)?;
        self.backend.trash(&item).map_err(|e| fail(e, None))?;
        self.overlay().hide(&parent.uuid, &item.uuid, None);
        Ok(())
    }

    /// Upload a local file. The caller owns conflict policy; providers keep
    /// their native same-name behaviour (Filen versions, Internxt conflicts).
    pub fn upload(
        &self,
        local: &Path,
        target_folder: &str,
        name: &str,
        transfer: Arc<Transfer>,
    ) -> CloudResult<u64> {
        paths::validate_name(name)?;
        let metadata = fs::metadata(local).map_err(|_| CloudError::new(ErrorCode::Io))?;
        if !metadata.is_file() {
            return Err(CloudError::new(ErrorCode::NotAFile));
        }
        let size = metadata.len();
        if size == 0 && self.backend.provider() == Provider::Internxt {
            // Internxt rejects zero-byte files on every plan (402 "You can
            // not have empty files"); fail before any request.
            return Err(CloudError::new(ErrorCode::EmptyFileUnsupported));
        }
        transfer.set_total(size);
        let folder = self.folder(target_folder, false)?;
        if transfer.is_cancelled() {
            return Err(CloudError::new(ErrorCode::Cancelled));
        }
        let file = File::open(local).map_err(|_| CloudError::new(ErrorCode::Io))?;
        let mut reader = CountingReader::new(file, transfer.clone());
        self.backend
            .upload(&folder, name, size, &mut reader)
            .map_err(|e| fail(e, Some(&transfer)))?;
        Ok(size)
    }

    /// Download into a private staging file beside `local`, then rename it
    /// into place. A failed, cancelled or short transfer never replaces an
    /// existing destination and removes its staging file.
    pub fn download(&self, path: &str, local: &Path, transfer: Arc<Transfer>) -> CloudResult<u64> {
        let item = self.stat(path)?;
        if item.is_dir {
            return Err(CloudError::new(ErrorCode::NotAFile));
        }
        transfer.set_total(item.size);
        let staging = staging_path(local)?;
        let result = (|| {
            let file = File::create(&staging).map_err(|_| CloudError::new(ErrorCode::Io))?;
            let mut writer = CountingWriter::new(file, transfer.clone());
            self.backend
                .download(&item, &mut writer)
                .map_err(|e| fail(e, Some(&transfer)))?;
            writer.flush().map_err(|_| CloudError::new(ErrorCode::Io))?;
            let written = writer.written;
            let file = writer.into_inner();
            file.sync_all()
                .map_err(|_| CloudError::new(ErrorCode::Io))?;
            drop(file);
            if written != item.size {
                return Err(CloudError::new(ErrorCode::Integrity));
            }
            if transfer.is_cancelled() {
                return Err(CloudError::new(ErrorCode::Cancelled));
            }
            fs::rename(&staging, local).map_err(|_| CloudError::new(ErrorCode::Io))?;
            Ok(written)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&staging);
        }
        result
    }
}

fn staging_path(local: &Path) -> CloudResult<PathBuf> {
    let parent = local
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    if !parent.is_dir() {
        return Err(CloudError::new(ErrorCode::Io));
    }
    let name = local
        .file_name()
        .ok_or_else(|| CloudError::new(ErrorCode::InvalidPath))?
        .to_string_lossy();
    let counter = STAGING_COUNTER.fetch_add(1, Ordering::Relaxed);
    Ok(parent.join(format!(
        ".{name}.crisp-part-{}-{counter}",
        std::process::id()
    )))
}

#[cfg(test)]
pub mod fake {
    //! In-memory backend used by engine and API tests.
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    #[derive(Default)]
    pub struct State {
        pub items: HashMap<String, (Entry, String, Vec<u8>)>, // uuid -> (entry, parent, data)
        pub next: u64,
        pub calls: Vec<String>,
        pub fail_next: Option<String>,
    }

    pub struct FakeBackend {
        pub state: Arc<Mutex<State>>,
        pub revision: AtomicU64,
    }

    impl FakeBackend {
        pub fn new() -> (Self, Arc<Mutex<State>>) {
            let state = Arc::new(Mutex::new(State::default()));
            (
                Self {
                    state: state.clone(),
                    revision: AtomicU64::new(1),
                },
                state,
            )
        }

        fn take_failure(state: &mut State) -> anyhow::Result<()> {
            if let Some(message) = state.fail_next.take() {
                anyhow::bail!(message);
            }
            Ok(())
        }
    }

    impl Backend for FakeBackend {
        fn provider(&self) -> Provider {
            Provider::Filen
        }
        fn account(&self) -> String {
            "fake@example.com".into()
        }
        fn root(&self) -> Entry {
            Entry::folder("root", "")
        }
        fn list(&self, folder: &Entry, _fresh: bool) -> anyhow::Result<Vec<Entry>> {
            let mut state = self.state.lock().unwrap();
            state.calls.push(format!("list:{}", folder.uuid));
            Self::take_failure(&mut state)?;
            let mut items: Vec<Entry> = state
                .items
                .values()
                .filter(|(_, parent, _)| *parent == folder.uuid)
                .map(|(entry, _, _)| entry.clone())
                .collect();
            items.sort_by(|a, b| a.name.cmp(&b.name));
            Ok(items)
        }
        fn create_folder(&self, parent: &Entry, name: &str) -> anyhow::Result<Entry> {
            let mut state = self.state.lock().unwrap();
            state.calls.push(format!("mkdir:{name}"));
            Self::take_failure(&mut state)?;
            state.next += 1;
            let entry = Entry::folder(&format!("d{}", state.next), name);
            state.items.insert(
                entry.uuid.clone(),
                (entry.clone(), parent.uuid.clone(), vec![]),
            );
            Ok(entry)
        }
        fn rename(&self, item: &Entry, new_name: &str) -> anyhow::Result<()> {
            let mut state = self.state.lock().unwrap();
            state.calls.push(format!("rename:{}", item.uuid));
            Self::take_failure(&mut state)?;
            let slot = state.items.get_mut(&item.uuid).unwrap();
            slot.0.name = new_name.into();
            Ok(())
        }
        fn move_to(&self, item: &Entry, folder: &Entry) -> anyhow::Result<()> {
            let mut state = self.state.lock().unwrap();
            state.calls.push(format!("move:{}", item.uuid));
            Self::take_failure(&mut state)?;
            state.items.get_mut(&item.uuid).unwrap().1 = folder.uuid.clone();
            Ok(())
        }
        fn trash(&self, item: &Entry) -> anyhow::Result<()> {
            let mut state = self.state.lock().unwrap();
            state.calls.push(format!("trash:{}", item.uuid));
            Self::take_failure(&mut state)?;
            state.items.remove(&item.uuid);
            Ok(())
        }
        fn upload(
            &self,
            parent: &Entry,
            name: &str,
            size: u64,
            reader: &mut dyn std::io::Read,
        ) -> anyhow::Result<()> {
            let mut data = Vec::new();
            reader.read_to_end(&mut data)?;
            anyhow::ensure!(data.len() as u64 == size, "short upload");
            let mut state = self.state.lock().unwrap();
            state.calls.push(format!("upload:{name}"));
            Self::take_failure(&mut state)?;
            state.next += 1;
            let entry = Entry {
                uuid: format!("f{}", state.next),
                name: name.into(),
                is_dir: false,
                size,
                modified_ms: Some(1_700_000_000_000),
                mime: Some(paths::guess_mime(name).into()),
                native: Native::None,
            };
            state
                .items
                .insert(entry.uuid.clone(), (entry, parent.uuid.clone(), data));
            Ok(())
        }
        fn download(&self, item: &Entry, writer: &mut dyn Write) -> anyhow::Result<u64> {
            let (data, failure) = {
                let mut state = self.state.lock().unwrap();
                state.calls.push(format!("download:{}", item.uuid));
                let failure = state.fail_next.take();
                (state.items[&item.uuid].2.clone(), failure)
            };
            let half = data.len() / 2;
            writer.write_all(&data[..half])?;
            if let Some(message) = failure {
                anyhow::bail!(message);
            }
            writer.write_all(&data[half..])?;
            Ok(data.len() as u64)
        }
        fn export_session(&self) -> anyhow::Result<serde_json::Value> {
            Ok(serde_json::json!({"fake": true}))
        }
        fn revision(&self) -> u64 {
            self.revision.load(Ordering::Relaxed)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::fake::*;
    use super::*;
    use std::sync::Mutex;

    fn engine() -> (Engine, Arc<Mutex<State>>) {
        let (backend, state) = FakeBackend::new();
        (Engine::new(Box::new(backend)), state)
    }

    fn upload_bytes(engine: &Engine, dir: &Path, folder: &str, name: &str, data: &[u8]) {
        let local = dir.join(format!("src-{name}"));
        fs::write(&local, data).unwrap();
        engine
            .upload(&local, folder, name, Arc::new(Transfer::default()))
            .unwrap();
    }

    #[test]
    fn mkdir_is_recursive_and_idempotent() {
        let (engine, state) = engine();
        let created = engine.mkdir("/a/b/c").unwrap();
        assert_eq!(created.name, "c");
        let again = engine.mkdir("a/b/c/").unwrap();
        assert_eq!(again.uuid, created.uuid);
        let mkdirs = state
            .lock()
            .unwrap()
            .calls
            .iter()
            .filter(|c| c.starts_with("mkdir"))
            .count();
        assert_eq!(mkdirs, 3);
        assert_eq!(engine.stat("/a/b").unwrap().name, "b");
    }

    #[test]
    fn mkdir_rejects_file_component_and_bad_names() {
        let (engine, _) = engine();
        let dir = tempfile::tempdir().unwrap();
        upload_bytes(&engine, dir.path(), "/", "file.txt", b"x");
        assert_eq!(
            engine.mkdir("/file.txt").unwrap_err().code,
            ErrorCode::AlreadyExists
        );
        assert_eq!(
            engine.mkdir("/a/../b").unwrap_err().code,
            ErrorCode::InvalidPath
        );
        assert_eq!(
            engine.mkdir("/a\\b").unwrap_err().code,
            ErrorCode::InvalidName
        );
    }

    #[test]
    fn stat_and_list_report_typed_errors() {
        let (engine, _) = engine();
        let dir = tempfile::tempdir().unwrap();
        engine.mkdir("/docs").unwrap();
        upload_bytes(&engine, dir.path(), "/docs", "a.txt", b"abc");
        assert_eq!(
            engine.stat("/missing").unwrap_err().code,
            ErrorCode::NotFound
        );
        assert_eq!(
            engine.list("/docs/a.txt", false).unwrap_err().code,
            ErrorCode::NotAFolder
        );
        assert_eq!(
            engine.stat("/docs/a.txt/x").unwrap_err().code,
            ErrorCode::NotAFolder
        );
        let listing = engine.list("/docs", true).unwrap();
        assert_eq!(listing.len(), 1);
        assert_eq!(listing[0].size, 3);
        assert_eq!(listing[0].mime.as_deref(), Some("text/plain"));
        assert!(engine.stat("/").unwrap().is_dir);
    }

    #[test]
    fn entry_json_shape() {
        let mut entry = Entry::folder("u", "n");
        let json = entry.to_json();
        assert_eq!(json["directory"], true);
        assert!(json.get("modified").is_none());
        entry.modified_ms = Some(5);
        entry.mime = Some("text/plain".into());
        let json = entry.to_json();
        assert_eq!(json["modified"], 5);
        assert_eq!(json["mime"], "text/plain");
    }

    #[test]
    fn rename_checks_conflicts_before_mutating() {
        let (engine, state) = engine();
        engine.mkdir("/a").unwrap();
        engine.mkdir("/b").unwrap();
        assert_eq!(
            engine.rename("/a", "b").unwrap_err().code,
            ErrorCode::AlreadyExists
        );
        assert!(!state
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|c| c.starts_with("rename")));
        engine.rename("/a", "c").unwrap();
        assert_eq!(engine.stat("/c").unwrap().name, "c");
        engine.rename("/c", "c").unwrap();
        assert_eq!(
            engine.rename("/", "x").unwrap_err().code,
            ErrorCode::RootMutation
        );
        assert_eq!(
            engine.rename("/c", "x/y").unwrap_err().code,
            ErrorCode::InvalidName
        );
    }

    #[test]
    fn move_validates_target_and_cycles() {
        let (engine, state) = engine();
        engine.mkdir("/a/inner").unwrap();
        engine.mkdir("/b").unwrap();
        assert_eq!(
            engine.move_into("/a", "/a/inner").unwrap_err().code,
            ErrorCode::InvalidPath
        );
        assert_eq!(
            engine.move_into("/a", "/a").unwrap_err().code,
            ErrorCode::InvalidPath
        );
        assert_eq!(
            engine.move_into("/", "/b").unwrap_err().code,
            ErrorCode::RootMutation
        );
        assert_eq!(
            engine.move_into("/a", "/missing").unwrap_err().code,
            ErrorCode::NotFound
        );
        engine.move_into("/a/inner", "/a").unwrap(); // already there: no-op
        assert!(!state
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|c| c.starts_with("move")));
        engine.move_into("/a/inner", "/b").unwrap();
        assert_eq!(engine.stat("/b/inner").unwrap().name, "inner");
        engine.mkdir("/a/inner").unwrap();
        assert_eq!(
            engine.move_into("/a/inner", "/b").unwrap_err().code,
            ErrorCode::AlreadyExists
        );
    }

    #[test]
    fn move_into_file_is_rejected() {
        let (engine, _) = engine();
        let dir = tempfile::tempdir().unwrap();
        engine.mkdir("/a").unwrap();
        upload_bytes(&engine, dir.path(), "/", "f.bin", b"1");
        assert_eq!(
            engine.move_into("/a", "/f.bin").unwrap_err().code,
            ErrorCode::NotAFolder
        );
    }

    #[test]
    fn trash_refuses_root_and_missing() {
        let (engine, _) = engine();
        assert_eq!(engine.trash("/").unwrap_err().code, ErrorCode::RootMutation);
        assert_eq!(engine.trash("/nope").unwrap_err().code, ErrorCode::NotFound);
        engine.mkdir("/x").unwrap();
        engine.trash("/x").unwrap();
        assert_eq!(engine.stat("/x").unwrap_err().code, ErrorCode::NotFound);
    }

    #[test]
    fn upload_then_download_round_trip_with_progress() {
        let (engine, _) = engine();
        let dir = tempfile::tempdir().unwrap();
        let data: Vec<u8> = (0..100_000u32).map(|v| v as u8).collect();
        let local = dir.path().join("in.bin");
        fs::write(&local, &data).unwrap();
        let up = Arc::new(Transfer::default());
        assert_eq!(
            engine.upload(&local, "/", "in.bin", up.clone()).unwrap(),
            100_000
        );
        assert_eq!(up.snapshot(), (100_000, 100_000));
        let out = dir.path().join("out.bin");
        let down = Arc::new(Transfer::default());
        assert_eq!(
            engine.download("/in.bin", &out, down.clone()).unwrap(),
            100_000
        );
        assert_eq!(fs::read(&out).unwrap(), data);
        assert_eq!(down.snapshot(), (100_000, 100_000));
        let leftovers: Vec<_> = fs::read_dir(dir.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains("crisp-part"))
            .collect();
        assert!(leftovers.is_empty());
    }

    #[test]
    fn upload_validates_inputs() {
        let (engine, _) = engine();
        let dir = tempfile::tempdir().unwrap();
        let local = dir.path().join("a");
        fs::write(&local, b"1").unwrap();
        let t = || Arc::new(Transfer::default());
        assert_eq!(
            engine.upload(&local, "/", "a/b", t()).unwrap_err().code,
            ErrorCode::InvalidName
        );
        assert_eq!(
            engine.upload(dir.path(), "/", "a", t()).unwrap_err().code,
            ErrorCode::NotAFile
        );
        assert_eq!(
            engine
                .upload(&dir.path().join("missing"), "/", "a", t())
                .unwrap_err()
                .code,
            ErrorCode::Io
        );
        assert_eq!(
            engine
                .upload(&local, "/missing", "a", t())
                .unwrap_err()
                .code,
            ErrorCode::NotFound
        );
    }

    #[test]
    fn cancelled_upload_reports_cancelled_and_does_not_create() {
        let (engine, state) = engine();
        let dir = tempfile::tempdir().unwrap();
        let local = dir.path().join("a");
        fs::write(&local, vec![1u8; 1000]).unwrap();
        let transfer = Arc::new(Transfer::default());
        transfer.cancel();
        assert_eq!(
            engine.upload(&local, "/", "a", transfer).unwrap_err().code,
            ErrorCode::Cancelled
        );
        assert!(state.lock().unwrap().items.is_empty());
    }

    #[test]
    fn failed_download_keeps_existing_destination_and_cleans_staging() {
        let (engine, state) = engine();
        let dir = tempfile::tempdir().unwrap();
        upload_bytes(&engine, dir.path(), "/", "r.bin", &[7u8; 64]);
        let out = dir.path().join("out.bin");
        fs::write(&out, b"previous").unwrap();
        state.lock().unwrap().fail_next = Some("Filen HTTP 503: unavailable".into());
        let error = engine
            .download("/r.bin", &out, Arc::new(Transfer::default()))
            .unwrap_err();
        assert_eq!(error.code, ErrorCode::Server);
        assert!(error.retryable);
        assert_eq!(fs::read(&out).unwrap(), b"previous");
        assert!(!fs::read_dir(dir.path()).unwrap().any(|e| e
            .unwrap()
            .file_name()
            .to_string_lossy()
            .contains("crisp-part")));
    }

    #[test]
    fn cancelled_download_is_cancelled_not_io() {
        let (engine, _) = engine();
        let dir = tempfile::tempdir().unwrap();
        upload_bytes(&engine, dir.path(), "/", "r.bin", &[7u8; 64]);
        let transfer = Arc::new(Transfer::default());
        transfer.cancel();
        let out = dir.path().join("out.bin");
        assert_eq!(
            engine.download("/r.bin", &out, transfer).unwrap_err().code,
            ErrorCode::Cancelled
        );
        assert!(!out.exists());
    }

    #[test]
    fn download_rejects_folders_and_missing_parent() {
        let (engine, _) = engine();
        engine.mkdir("/d").unwrap();
        let dir = tempfile::tempdir().unwrap();
        let t = || Arc::new(Transfer::default());
        assert_eq!(
            engine
                .download("/d", &dir.path().join("x"), t())
                .unwrap_err()
                .code,
            ErrorCode::NotAFile
        );
        let tmp = tempfile::tempdir().unwrap();
        upload_bytes(&engine, tmp.path(), "/", "f", b"1");
        assert_eq!(
            engine
                .download("/f", &dir.path().join("no/such/dir/x"), t())
                .unwrap_err()
                .code,
            ErrorCode::Io
        );
    }

    #[test]
    fn backend_errors_are_classified() {
        let (engine, state) = engine();
        state.lock().unwrap().fail_next = Some("Filen HTTP 401: expired".into());
        assert_eq!(
            engine.list("/", false).unwrap_err().code,
            ErrorCode::SessionExpired
        );
        state.lock().unwrap().fail_next = Some("Internxt folder endpoint returned 500 x".into());
        let error = engine.mkdir("/t").unwrap_err();
        assert_eq!(error.code, ErrorCode::Server);
        assert!(error.retryable);
        engine.mkdir("/t").unwrap();
        engine.stat("/t").unwrap();
    }

    #[test]
    fn info_reports_identity_without_secrets() {
        let (engine, _) = engine();
        let info = engine.info();
        assert_eq!(info["provider"], "filen");
        assert_eq!(info["account"], "fake@example.com");
        assert_eq!(info["root"], "root");
        assert_eq!(engine.revision(), 1);
        assert_eq!(engine.export_session().unwrap()["fake"], true);
    }

    #[test]
    fn staging_names_are_hidden_unique_and_local() {
        let dir = tempfile::tempdir().unwrap();
        let a = staging_path(&dir.path().join("x.bin")).unwrap();
        let b = staging_path(&dir.path().join("x.bin")).unwrap();
        assert_ne!(a, b);
        assert_eq!(a.parent(), Some(dir.path()));
        assert!(a
            .file_name()
            .unwrap()
            .to_string_lossy()
            .starts_with(".x.bin.crisp-part-"));
        assert_eq!(
            staging_path(&dir.path().join("missing/x"))
                .unwrap_err()
                .code,
            ErrorCode::Io
        );
    }

    fn file(uuid: &str, name: &str) -> Entry {
        Entry {
            is_dir: false,
            ..Entry::folder(uuid, name)
        }
    }

    #[test]
    fn overlay_shows_a_created_folder_until_the_listing_has_it() {
        let mut overlay = Overlay::default();
        overlay.add("root", Entry::folder("new", "Docs"));
        // Lagging listing: the folder is still missing.
        let listed = overlay.apply("root", vec![file("a", "a.txt")]);
        assert_eq!(
            listed.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(),
            ["a.txt", "Docs"]
        );
        // Listing caught up: no duplicate, and the overlay entry is dropped.
        let listed = overlay.apply("root", vec![Entry::folder("new", "Docs")]);
        assert_eq!(listed.len(), 1);
        assert!(overlay.added.get("root").unwrap().is_empty());
        // Other folders are not affected.
        assert!(overlay.apply("other", vec![]).is_empty());
    }

    #[test]
    fn overlay_hides_trashed_items_until_the_listing_drops_them() {
        let mut overlay = Overlay::default();
        overlay.hide("root", "a", None);
        assert!(overlay.apply("root", vec![file("a", "a.txt")]).is_empty());
        assert!(overlay.apply("root", vec![]).is_empty());
        assert!(overlay.hidden.get("root").unwrap().is_empty());
        // A later item that reuses the uuid is visible again.
        assert_eq!(overlay.apply("root", vec![file("a", "a.txt")]).len(), 1);
    }

    #[test]
    fn overlay_rename_hides_only_the_old_name() {
        let mut overlay = Overlay::default();
        overlay.hide("root", "a", Some("old.txt"));
        overlay.add("root", file("a", "new.txt"));
        let names = |items: Vec<Entry>| items.into_iter().map(|e| e.name).collect::<Vec<_>>();
        assert_eq!(
            names(overlay.apply("root", vec![file("a", "old.txt")])),
            ["new.txt"]
        );
        assert_eq!(
            names(overlay.apply("root", vec![file("a", "new.txt")])),
            ["new.txt"]
        );
    }

    #[test]
    fn overlay_expires_stale_entries() {
        let mut overlay = Overlay::default();
        let past = Instant::now() - OVERLAY_TTL - Duration::from_secs(1);
        overlay
            .added
            .insert("root".into(), vec![(Entry::folder("x", "Ghost"), past)]);
        overlay
            .hidden
            .insert("root".into(), vec![("a".into(), None, past)]);
        let listed = overlay.apply("root", vec![file("a", "a.txt")]);
        assert_eq!(
            listed.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(),
            ["a.txt"]
        );
    }

    #[test]
    fn overlay_move_hides_in_source_and_adds_in_target() {
        let mut overlay = Overlay::default();
        overlay.hide("src", "a", None);
        overlay.add("dst", file("a", "a.txt"));
        assert!(overlay.apply("src", vec![file("a", "a.txt")]).is_empty());
        assert_eq!(overlay.apply("dst", vec![]).len(), 1);
    }
}
