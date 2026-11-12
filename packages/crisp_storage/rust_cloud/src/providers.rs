//! Filen and Internxt implementations of [`Backend`].
use crate::engine::{Backend, Entry, Native};
use crate::error::{CloudError, CloudResult, ErrorCode};
use crate::paths;
use crate::session::{Provider, SessionEnvelope};
use crisp_filen::{FilenNativeClient, FilenSession};
use crisp_internxt::{InternxtNativeClient, InternxtSession};
use std::io::{Read, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, RwLock};

// ----------------------------------------------------------------- Filen --

pub struct FilenBackend {
    client: FilenNativeClient,
    session: FilenSession,
}

fn filen_entry(item: crisp_filen::NativeItem) -> Entry {
    Entry {
        uuid: item.uuid.clone(),
        name: item.name.clone(),
        is_dir: item.is_dir,
        size: if item.is_dir { 0 } else { item.size },
        modified_ms: (item.modified > 0).then_some(item.modified),
        mime: (!item.is_dir && !item.mime.is_empty()).then(|| item.mime.clone()),
        native: Native::Filen(Box::new(item)),
    }
}

fn filen_item(entry: &Entry) -> CloudResult<&crisp_filen::NativeItem> {
    match &entry.native {
        Native::Filen(item) => Ok(item),
        _ => Err(CloudError::new(ErrorCode::RootMutation)),
    }
}

impl FilenBackend {
    pub fn login(
        email: &str,
        password: &str,
        tfa: Option<&str>,
    ) -> anyhow::Result<SessionEnvelope> {
        let session =
            FilenNativeClient::login(crisp_filen::DEFAULT_GATEWAY_URL, email, password, tfa)?;
        Ok(SessionEnvelope::new(
            Provider::Filen,
            &session.email,
            serde_json::to_value(&session)?,
        ))
    }

    pub fn open(envelope: &SessionEnvelope) -> CloudResult<Self> {
        let session: FilenSession = serde_json::from_value(envelope.session.clone())
            .map_err(|_| CloudError::new(ErrorCode::InvalidSession))?;
        if session.email != envelope.account
            || session.api_key.is_empty()
            || session.root_folder_uuid.is_empty()
            || session.master_keys.is_empty() && session.dek.is_none()
        {
            return Err(CloudError::new(ErrorCode::InvalidSession));
        }
        let client = FilenNativeClient::from_session(&session)
            .map_err(|_| CloudError::new(ErrorCode::InvalidSession))?;
        Ok(Self { client, session })
    }
}

impl Backend for FilenBackend {
    fn provider(&self) -> Provider {
        Provider::Filen
    }
    fn account(&self) -> String {
        self.session.email.clone()
    }
    fn root(&self) -> Entry {
        Entry::folder(&self.session.root_folder_uuid, "")
    }
    fn list(&self, folder: &Entry, fresh: bool) -> anyhow::Result<Vec<Entry>> {
        let items = if fresh {
            self.client.list_folder_fresh(&folder.uuid)?
        } else {
            self.client.list_folder(&folder.uuid)?
        };
        Ok(items.into_iter().map(filen_entry).collect())
    }
    fn create_folder(&self, parent: &Entry, name: &str) -> anyhow::Result<Entry> {
        let uuid = self.client.create_folder(&parent.uuid, name)?;
        Ok(Entry::folder(&uuid, name))
    }
    fn rename(&self, item: &Entry, new_name: &str) -> anyhow::Result<()> {
        self.client.rename_item(filen_item(item)?, new_name)
    }
    fn move_to(&self, item: &Entry, folder: &Entry) -> anyhow::Result<()> {
        self.client.move_item(&item.uuid, &folder.uuid, item.is_dir)
    }
    fn trash(&self, item: &Entry) -> anyhow::Result<()> {
        self.client
            .trash(&item.uuid, if item.is_dir { "folder" } else { "file" })
    }
    fn upload(
        &self,
        parent: &Entry,
        name: &str,
        size: u64,
        reader: &mut dyn Read,
    ) -> anyhow::Result<()> {
        self.client.upload_file_from_reader(
            &parent.uuid,
            name,
            paths::guess_mime(name),
            size,
            reader,
        )
    }
    fn download(&self, item: &Entry, writer: &mut dyn Write) -> anyhow::Result<u64> {
        let mut writer = writer;
        self.client
            .download_file_to_writer(filen_item(item)?, &mut writer)
    }
    fn export_session(&self) -> anyhow::Result<serde_json::Value> {
        Ok(serde_json::to_value(&self.session)?)
    }
    fn revision(&self) -> u64 {
        // Filen API keys are long-lived; the session never changes in place.
        1
    }
}

// -------------------------------------------------------------- Internxt --

pub struct InternxtBackend {
    state: RwLock<(InternxtNativeClient, InternxtSession)>,
    refresh: Mutex<()>,
    revision: AtomicU64,
}

/// Same predicate as the upstream client's private `is_expired_token_error`.
/// Stricter than upstream: only an HTTP 401 status or explicit expiry text
/// counts, never a `401` that happens to appear in an id or byte count.
pub fn is_expired_token(error: &anyhow::Error) -> bool {
    let text = format!("{error:#}").to_ascii_lowercase();
    let status_401 = ["returned 401", "http 401", "status 401", "status: 401"]
        .iter()
        .any(|marker| {
            text.match_indices(marker).any(|(index, _)| {
                !text[index + marker.len()..]
                    .chars()
                    .next()
                    .is_some_and(|c| c.is_ascii_digit())
            })
        });
    status_401 || text.contains("unauthorized") || text.contains("token expired")
}

fn parse_rfc3339_ms(value: &str) -> Option<i64> {
    chrono::DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|date| date.timestamp_millis())
}

fn internxt_entry(item: crisp_internxt::NativeItem) -> Entry {
    Entry {
        uuid: item.uuid.clone(),
        name: item.name.clone(),
        is_dir: item.is_dir,
        size: if item.is_dir { 0 } else { item.size },
        modified_ms: item.modified_at.as_deref().and_then(parse_rfc3339_ms),
        mime: None,
        native: Native::Internxt(Box::new(item)),
    }
}

impl InternxtBackend {
    pub fn login(
        email: &str,
        password: &str,
        tfa: Option<&str>,
    ) -> anyhow::Result<SessionEnvelope> {
        let session = InternxtNativeClient::login_without_keys(
            crisp_internxt::DEFAULT_DRIVE_API_URL,
            email,
            password,
            tfa,
        )?;
        Ok(SessionEnvelope::new(
            Provider::Internxt,
            &session.email,
            serde_json::to_value(&session)?,
        ))
    }

    pub fn open(envelope: &SessionEnvelope) -> CloudResult<Self> {
        let session: InternxtSession = serde_json::from_value(envelope.session.clone())
            .map_err(|_| CloudError::new(ErrorCode::InvalidSession))?;
        if session.email != envelope.account
            || session.active_token().is_empty()
            || session.root_folder_id.is_empty()
            || session.bucket_bytes().is_err()
            || session.mnemonic.is_empty()
        {
            return Err(CloudError::new(ErrorCode::InvalidSession));
        }
        let client = InternxtNativeClient::new(&session.drive_api_url, session.active_token())
            .map_err(|_| CloudError::new(ErrorCode::InvalidSession))?;
        Ok(Self {
            state: RwLock::new((client, session)),
            refresh: Mutex::new(()),
            revision: AtomicU64::new(1),
        })
    }

    fn snapshot(&self) -> (InternxtNativeClient, InternxtSession) {
        let guard = self.state.read().unwrap_or_else(|e| e.into_inner());
        (guard.0.clone(), guard.1.clone())
    }

    /// Run `op`; on an expired bearer token renew the session once
    /// (single-flight) and, only when `replay` is true, repeat the operation.
    /// Replay is limited to single-request operations, which the gateway
    /// rejected outright. Multi-request uploads/downloads are never replayed;
    /// they report a retryable `SessionExpired` after the renewal.
    fn run<T>(
        &self,
        replay: bool,
        op: impl Fn(&InternxtNativeClient, &InternxtSession) -> anyhow::Result<T>,
    ) -> anyhow::Result<T> {
        let (client, session) = self.snapshot();
        let first = op(&client, &session);
        match first {
            Err(error) if is_expired_token(&error) => {
                let _single = self.refresh.lock().unwrap_or_else(|e| e.into_inner());
                let (current_client, current) = self.snapshot();
                let (client, session) = if current.active_token() != session.active_token() {
                    (current_client, current)
                } else {
                    let renewed = current_client
                        .refresh_session(&current)
                        .map_err(|_| CloudError::new(ErrorCode::SessionExpired))?;
                    let client =
                        InternxtNativeClient::new(&renewed.drive_api_url, renewed.active_token())?;
                    *self.state.write().unwrap_or_else(|e| e.into_inner()) =
                        (client.clone(), renewed.clone());
                    self.revision.fetch_add(1, Ordering::AcqRel);
                    (client, renewed)
                };
                if replay {
                    op(&client, &session)
                } else {
                    Err(CloudError::new(ErrorCode::SessionExpired)
                        .retryable(true)
                        .into())
                }
            }
            other => other,
        }
    }
}

impl Backend for InternxtBackend {
    fn provider(&self) -> Provider {
        Provider::Internxt
    }
    fn account(&self) -> String {
        self.snapshot().1.email
    }
    fn root(&self) -> Entry {
        Entry::folder(&self.snapshot().1.root_folder_id, "")
    }
    fn list(&self, folder: &Entry, fresh: bool) -> anyhow::Result<Vec<Entry>> {
        let items = self.run(true, |client, _| {
            if fresh {
                client.clear_listing_cache();
                client.list_folder(&folder.uuid)
            } else {
                client.list_folder_cached(&folder.uuid)
            }
        })?;
        Ok(items.into_iter().map(internxt_entry).collect())
    }
    fn create_folder(&self, parent: &Entry, name: &str) -> anyhow::Result<Entry> {
        let uuid = self.run(true, |client, _| client.create_folder(&parent.uuid, name))?;
        Ok(Entry::folder(&uuid, name))
    }
    fn rename(&self, item: &Entry, new_name: &str) -> anyhow::Result<()> {
        self.run(true, |client, _| {
            if item.is_dir {
                client.rename_folder(&item.uuid, new_name)
            } else {
                let (plain, kind) = paths::split_extension(new_name);
                client.rename_file(&item.uuid, plain, kind)
            }
        })
    }
    fn move_to(&self, item: &Entry, folder: &Entry) -> anyhow::Result<()> {
        self.run(true, |client, _| {
            if item.is_dir {
                client.move_folder(&item.uuid, &folder.uuid)
            } else {
                client.move_file(&item.uuid, &folder.uuid)
            }
        })
    }
    fn trash(&self, item: &Entry) -> anyhow::Result<()> {
        self.run(true, |client, _| {
            client.trash(&item.uuid, if item.is_dir { "folder" } else { "file" })
        })
    }
    fn upload(
        &self,
        parent: &Entry,
        name: &str,
        size: u64,
        reader: &mut dyn Read,
    ) -> anyhow::Result<()> {
        let (plain, kind) = paths::split_extension(name);
        let reader = std::cell::RefCell::new(reader);
        self.run(false, |client, session| {
            let mut guard = reader.borrow_mut();
            let r: &mut dyn Read = &mut **guard;
            client.upload_reader(session, &parent.uuid, plain, kind, r, size)
        })
    }
    fn download(&self, item: &Entry, writer: &mut dyn Write) -> anyhow::Result<u64> {
        let writer = std::cell::RefCell::new(writer);
        self.run(false, |client, session| {
            let mut guard = writer.borrow_mut();
            let w: &mut dyn Write = &mut **guard;
            client.download_file_to_writer(session, &item.uuid, w)
        })
    }
    fn export_session(&self) -> anyhow::Result<serde_json::Value> {
        Ok(serde_json::to_value(&self.snapshot().1)?)
    }
    fn revision(&self) -> u64 {
        self.revision.load(Ordering::Acquire)
    }
}

pub fn open(envelope: &SessionEnvelope) -> CloudResult<Box<dyn Backend>> {
    Ok(match envelope.provider {
        Provider::Filen => Box::new(FilenBackend::open(envelope)?),
        Provider::Internxt => Box::new(InternxtBackend::open(envelope)?),
    })
}

pub fn login(
    provider: Provider,
    email: &str,
    password: &str,
    tfa: Option<&str>,
) -> anyhow::Result<SessionEnvelope> {
    if email.trim().is_empty() || password.is_empty() {
        return Err(CloudError::new(ErrorCode::InvalidArgument).into());
    }
    let tfa = tfa.map(str::trim).filter(|code| !code.is_empty());
    match provider {
        Provider::Filen => FilenBackend::login(email.trim(), password, tfa),
        Provider::Internxt => InternxtBackend::login(email.trim(), password, tfa),
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;

    pub fn filen_envelope() -> SessionEnvelope {
        let session = FilenSession {
            gateway_url: "http://127.0.0.1:9".into(),
            ingest_url: "http://127.0.0.1:9".into(),
            egest_url: "http://127.0.0.1:9".into(),
            email: "f@example.com".into(),
            api_key: "key".into(),
            auth_version: 2,
            file_encryption_version: 2,
            metadata_encryption_version: 2,
            root_folder_uuid: "root-f".into(),
            master_keys: vec![b"master".to_vec()],
            dek: None,
            kek: None,
            private_key: None,
            hmac_key: None,
        };
        SessionEnvelope::new(
            Provider::Filen,
            "f@example.com",
            serde_json::to_value(session).unwrap(),
        )
    }

    pub fn internxt_envelope() -> SessionEnvelope {
        let session = InternxtSession {
            drive_api_url: "http://127.0.0.1:9/drive".into(),
            network_url: "http://127.0.0.1:9/network".into(),
            email: "i@example.com".into(),
            token: "old".into(),
            new_token: "new".into(),
            mnemonic: "abandon abandon".into(),
            user_id: "user".into(),
            root_folder_id: "root-i".into(),
            bridge_user: "bridge".into(),
            bucket_id: "00112233445566778899aabb".into(),
        };
        SessionEnvelope::new(
            Provider::Internxt,
            "i@example.com",
            serde_json::to_value(session).unwrap(),
        )
    }

    #[test]
    fn opens_filen_session_without_network() {
        let backend = FilenBackend::open(&filen_envelope()).unwrap();
        assert_eq!(backend.account(), "f@example.com");
        assert_eq!(backend.root().uuid, "root-f");
        assert_eq!(backend.revision(), 1);
        assert_eq!(backend.export_session().unwrap()["api_key"], "key");
    }

    #[test]
    fn opens_internxt_session_without_network() {
        let backend = InternxtBackend::open(&internxt_envelope()).unwrap();
        assert_eq!(backend.account(), "i@example.com");
        assert_eq!(backend.root().uuid, "root-i");
        assert_eq!(backend.export_session().unwrap()["new_token"], "new");
    }

    #[test]
    fn rejects_identity_mismatch_and_incomplete_sessions() {
        let mut envelope = filen_envelope();
        envelope.account = "other@example.com".into();
        assert_eq!(
            FilenBackend::open(&envelope).err().unwrap().code,
            ErrorCode::InvalidSession
        );
        let mut envelope = filen_envelope();
        envelope.session["api_key"] = "".into();
        assert_eq!(
            FilenBackend::open(&envelope).err().unwrap().code,
            ErrorCode::InvalidSession
        );
        let mut envelope = internxt_envelope();
        envelope.session["bucket_id"] = "zz".into();
        assert_eq!(
            InternxtBackend::open(&envelope).err().unwrap().code,
            ErrorCode::InvalidSession
        );
        let mut envelope = internxt_envelope();
        envelope.session["mnemonic"] = "".into();
        assert_eq!(
            InternxtBackend::open(&envelope).err().unwrap().code,
            ErrorCode::InvalidSession
        );
        let mut envelope = internxt_envelope();
        envelope.session = serde_json::json!({"token": "t"});
        assert_eq!(
            InternxtBackend::open(&envelope).err().unwrap().code,
            ErrorCode::InvalidSession
        );
    }

    #[test]
    fn login_rejects_empty_credentials_before_network() {
        let error = login(Provider::Filen, " ", "pw", None).unwrap_err();
        assert_eq!(
            crate::error::classify(&error).code,
            ErrorCode::InvalidArgument
        );
        let error = login(Provider::Internxt, "a@b", "", None).unwrap_err();
        assert_eq!(
            crate::error::classify(&error).code,
            ErrorCode::InvalidArgument
        );
    }

    #[test]
    fn expired_token_predicate() {
        assert!(is_expired_token(&anyhow::anyhow!(
            "Internxt list returned 401 Unauthorized"
        )));
        assert!(is_expired_token(&anyhow::anyhow!("token expired")));
        assert!(!is_expired_token(&anyhow::anyhow!("returned 4010 bytes")));
        assert!(!is_expired_token(&anyhow::anyhow!("folder 401 not empty")));
        assert!(is_expired_token(&anyhow::anyhow!("Filen HTTP 401: x")));
        assert!(!is_expired_token(&anyhow::anyhow!(
            "returned 403 Forbidden"
        )));
    }

    #[test]
    fn entry_mapping() {
        let item = crisp_internxt::NativeItem {
            name: "a.txt".into(),
            uuid: "u".into(),
            is_dir: false,
            size: 3,
            modified_at: Some("2024-01-02T03:04:05.000Z".into()),
        };
        let entry = internxt_entry(item);
        assert_eq!(entry.modified_ms, Some(1_704_164_645_000));
        assert_eq!(entry.size, 3);
        let folder = internxt_entry(crisp_internxt::NativeItem {
            name: "d".into(),
            uuid: "d".into(),
            is_dir: true,
            size: 99,
            modified_at: Some("garbage".into()),
        });
        assert_eq!(folder.size, 0);
        assert_eq!(folder.modified_ms, None);
    }

    #[test]
    fn root_entries_cannot_be_renamed_through_filen() {
        let backend = FilenBackend::open(&filen_envelope()).unwrap();
        let error = backend.rename(&backend.root(), "x").unwrap_err();
        assert_eq!(crate::error::classify(&error).code, ErrorCode::RootMutation);
    }

    #[test]
    fn unreachable_gateway_maps_to_network_error() {
        // 127.0.0.1:9 (discard) is closed on CI and developer machines.
        let backend = InternxtBackend::open(&internxt_envelope()).unwrap();
        let error = backend.list(&backend.root(), true).unwrap_err();
        let code = crate::error::classify(&error).code;
        assert!(
            matches!(code, ErrorCode::Network | ErrorCode::Provider),
            "{code:?}"
        );
    }
}
