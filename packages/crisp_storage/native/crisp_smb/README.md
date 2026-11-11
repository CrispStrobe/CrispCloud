# crisp_smb (experimental)

Independent MIT OR Apache-2.0 SMB engine, shared by Flutter's generated bridge
and Rust consumers. The application keeps libsmb2 as its default until the
qualification matrix in `../../../../docs/SMB_RUST_ROLLOUT.md` passes.

- Pins `smb2` 0.43.0; no Samba/libsmb2 dependency in this crate.
- Named authentication, mandatory signing, encryption required unless explicitly
  disabled in the connection. Guest sessions and DFS referrals are rejected.
- No automatic reconnect/replay of mutations. Session cancellation terminates
  the session; create a new session to resume.
- JSON carries metadata only; positioned reads/writes use at most 256 KiB.
- Direct downloads keep file bytes native, use four bounded read-ahead chunks,
  and validate identity/version before resume and after completion.
- Downloads write a caller-owned staging file, never publish a completed file.
  Keep the `.resume` sidecar with the partial file. Other backends' validators
  are incompatible and cause a safe restart. Uploads are not resumable/atomic.
- One operation at a time per session; at most eight open file handles.

Run `cargo test --locked`. This does not prove interoperability or security on
real SMB3 servers; those checks remain a rollout gate. No credentials are logged
or persisted by the wrapper. The caller owns secure credential storage.
