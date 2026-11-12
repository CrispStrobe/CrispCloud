//! Transfer handles: coalesced progress counters and cooperative cancellation.
//!
//! Dart polls [`progress`] (sync, cheap) and calls [`cancel`]. The blocking
//! transfer observes cancellation at every read/write boundary through the
//! wrappers below, so a cancelled job stops at the next buffer even when the
//! upstream client offers no cancellation hook of its own.
use crate::error::{CloudError, CloudResult, ErrorCode};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

pub const CANCELLED_MARKER: &str = "crisp-cloud-transfer-cancelled";
pub const MAX_TRANSFERS: usize = 256;

#[derive(Debug, Default)]
pub struct Transfer {
    pub done: AtomicU64,
    pub total: AtomicU64,
    pub cancelled: AtomicBool,
}

impl Transfer {
    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }
    pub fn set_total(&self, total: u64) {
        self.total.store(total, Ordering::Release);
    }
    pub fn add(&self, bytes: u64) {
        self.done.fetch_add(bytes, Ordering::AcqRel);
    }
    pub fn snapshot(&self) -> (u64, u64) {
        (
            self.done.load(Ordering::Acquire),
            self.total.load(Ordering::Acquire),
        )
    }
    pub fn check(&self) -> std::io::Result<()> {
        if self.is_cancelled() {
            Err(std::io::Error::other(CANCELLED_MARKER))
        } else {
            Ok(())
        }
    }
}

#[derive(Default)]
pub struct TransferRegistry {
    next: AtomicU64,
    items: Mutex<HashMap<u64, Arc<Transfer>>>,
}

impl TransferRegistry {
    pub fn create(&self) -> CloudResult<u64> {
        let mut items = self
            .items
            .lock()
            .map_err(|_| CloudError::new(ErrorCode::Internal))?;
        if items.len() >= MAX_TRANSFERS {
            return Err(CloudError::new(ErrorCode::Busy));
        }
        let id = self.next.fetch_add(1, Ordering::Relaxed) + 1;
        items.insert(id, Arc::new(Transfer::default()));
        Ok(id)
    }

    pub fn get(&self, id: u64) -> CloudResult<Arc<Transfer>> {
        self.items
            .lock()
            .map_err(|_| CloudError::new(ErrorCode::Internal))?
            .get(&id)
            .cloned()
            .ok_or_else(|| CloudError::new(ErrorCode::Closed))
    }

    pub fn release(&self, id: u64) -> CloudResult<()> {
        self.items
            .lock()
            .map_err(|_| CloudError::new(ErrorCode::Internal))?
            .remove(&id);
        Ok(())
    }

    pub fn len(&self) -> usize {
        self.items.lock().map(|items| items.len()).unwrap_or(0)
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

pub fn registry() -> &'static TransferRegistry {
    static REGISTRY: OnceLock<TransferRegistry> = OnceLock::new();
    REGISTRY.get_or_init(TransferRegistry::default)
}

pub struct CountingReader<R> {
    inner: R,
    transfer: Arc<Transfer>,
}

impl<R> CountingReader<R> {
    pub fn new(inner: R, transfer: Arc<Transfer>) -> Self {
        Self { inner, transfer }
    }
}

impl<R: Read> Read for CountingReader<R> {
    fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
        self.transfer.check()?;
        let read = self.inner.read(buffer)?;
        self.transfer.add(read as u64);
        Ok(read)
    }
}

pub struct CountingWriter<W> {
    inner: W,
    transfer: Arc<Transfer>,
    pub written: u64,
}

impl<W> CountingWriter<W> {
    pub fn new(inner: W, transfer: Arc<Transfer>) -> Self {
        Self {
            inner,
            transfer,
            written: 0,
        }
    }
    pub fn into_inner(self) -> W {
        self.inner
    }
}

impl<W: Write> Write for CountingWriter<W> {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        self.transfer.check()?;
        let written = self.inner.write(buffer)?;
        self.written += written as u64;
        self.transfer.add(written as u64);
        Ok(written)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.inner.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_creates_unique_ids_and_releases() {
        let registry = TransferRegistry::default();
        let a = registry.create().unwrap();
        let b = registry.create().unwrap();
        assert_ne!(a, b);
        assert_eq!(registry.len(), 2);
        registry.release(a).unwrap();
        assert_eq!(registry.get(a).unwrap_err().code, ErrorCode::Closed);
        registry.get(b).unwrap();
        registry.release(a).unwrap();
    }

    #[test]
    fn registry_is_bounded() {
        let registry = TransferRegistry::default();
        for _ in 0..MAX_TRANSFERS {
            registry.create().unwrap();
        }
        assert_eq!(registry.create().unwrap_err().code, ErrorCode::Busy);
    }

    #[test]
    fn counting_reader_reports_progress_and_stops_on_cancel() {
        let transfer = Arc::new(Transfer::default());
        transfer.set_total(10);
        let mut reader = CountingReader::new(&b"0123456789"[..], transfer.clone());
        let mut buffer = [0u8; 4];
        assert_eq!(reader.read(&mut buffer).unwrap(), 4);
        assert_eq!(transfer.snapshot(), (4, 10));
        transfer.cancel();
        let error = reader.read(&mut buffer).unwrap_err();
        assert!(error.to_string().contains(CANCELLED_MARKER));
        assert_eq!(transfer.snapshot(), (4, 10));
    }

    #[test]
    fn counting_writer_counts_and_cancels() {
        let transfer = Arc::new(Transfer::default());
        let mut writer = CountingWriter::new(Vec::new(), transfer.clone());
        writer.write_all(b"hello").unwrap();
        assert_eq!(writer.written, 5);
        assert_eq!(transfer.snapshot().0, 5);
        transfer.cancel();
        assert!(writer.write_all(b"x").is_err());
        assert_eq!(writer.into_inner(), b"hello");
    }
}
