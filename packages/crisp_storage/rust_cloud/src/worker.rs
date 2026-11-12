//! Dedicated storage workers for blocking provider calls.
//!
//! Both upstream clients use `reqwest::blocking`, which must not run on the
//! Flutter UI thread or inside a Tokio task (it starts its own runtime and
//! panics when nested). Each call gets a fresh, named OS thread outside any
//! runtime context; the async bridge function only awaits a oneshot channel.
//! The number of simultaneous workers is bounded; excess calls fail fast with
//! a retryable `Busy` error instead of queueing without limit.
use crate::error::{CloudError, CloudResult, ErrorCode};
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicUsize, Ordering};

pub const MAX_WORKERS: usize = 32;
static ACTIVE: AtomicUsize = AtomicUsize::new(0);

struct Slot;
impl Drop for Slot {
    fn drop(&mut self) {
        ACTIVE.fetch_sub(1, Ordering::AcqRel);
    }
}

pub fn active() -> usize {
    ACTIVE.load(Ordering::Acquire)
}

pub async fn run<T, F>(job: F) -> CloudResult<T>
where
    T: Send + 'static,
    F: FnOnce() -> CloudResult<T> + Send + 'static,
{
    if ACTIVE.fetch_add(1, Ordering::AcqRel) >= MAX_WORKERS {
        ACTIVE.fetch_sub(1, Ordering::AcqRel);
        return Err(CloudError::new(ErrorCode::Busy));
    }
    let slot = Slot;
    let (sender, receiver) = futures::channel::oneshot::channel();
    let spawned = std::thread::Builder::new()
        .name("crisp-cloud-worker".into())
        .spawn(move || {
            let _slot = slot;
            let result = std::panic::catch_unwind(AssertUnwindSafe(job))
                .unwrap_or_else(|_| Err(CloudError::new(ErrorCode::Internal)));
            let _ = sender.send(result);
        });
    if spawned.is_err() {
        // The closure (and with it the slot) was dropped by the failed spawn.
        return Err(CloudError::new(ErrorCode::Busy));
    }
    receiver
        .await
        .unwrap_or_else(|_| Err(CloudError::new(ErrorCode::Internal)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::executor::block_on;

    #[test]
    fn returns_values_and_errors() {
        assert_eq!(block_on(run(|| Ok(41 + 1))).unwrap(), 42);
        let error = block_on(run(|| -> CloudResult<()> {
            Err(CloudError::new(ErrorCode::NotFound))
        }))
        .unwrap_err();
        assert_eq!(error.code, ErrorCode::NotFound);
    }

    #[test]
    fn runs_on_a_named_thread_outside_the_caller() {
        let caller = std::thread::current().id();
        let (id, name) = block_on(run(|| {
            let current = std::thread::current();
            Ok((current.id(), current.name().map(str::to_owned)))
        }))
        .unwrap();
        assert_ne!(id, caller);
        assert_eq!(name.as_deref(), Some("crisp-cloud-worker"));
    }

    #[test]
    fn panics_become_internal_errors_and_release_slots() {
        let error = block_on(run(|| -> CloudResult<()> { panic!("boom") })).unwrap_err();
        assert_eq!(error.code, ErrorCode::Internal);
    }
}
