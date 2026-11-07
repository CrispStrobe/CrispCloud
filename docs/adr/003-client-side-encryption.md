# ADR 003: Client-Side Encryption with AES-256-GCM, PBKDF2, and BIP39

**Status**: Accepted

---

## Context

CrispCloud connects to providers that store files on servers the user does not control. Even with TLS in transit and at-rest encryption on the server side, the provider can access file contents and metadata. Users with strong privacy requirements need a guarantee that the provider sees only opaque ciphertext.

Several design decisions needed to be made:

1. **Where to encrypt**: client-side (before upload) or server-side (by provider)?
2. **Which cipher**: AES-128-CBC, AES-256-GCM, ChaCha20-Poly1305, or XSalsa20?
3. **How to derive keys**: from a passphrase using PBKDF2, Argon2id, or scrypt?
4. **How to back up keys**: raw hex, PEM, or a mnemonic standard?
5. **How to handle encrypted filenames**: always, never, or optionally?

**Server-side encryption** was rejected because it requires the server to hold the key, which defeats the purpose for untrusted providers.

**AES-CBC** requires a separate, correctly composed authentication mechanism. This application uses AES-256-GCM for authenticated encryption and its existing file-format compatibility; this is not a claim that a 128-bit AES key is intrinsically insecure.

**ChaCha20-Poly1305** was considered. It is excellent (used in TLS 1.3, WireGuard) but AES-256-GCM is more widely understood, more universally supported in hardware (AES-NI), and the `cryptography` package exposes it through OS-accelerated implementations on all platforms.

**Argon2id** and **scrypt** are memory-hard alternatives. The existing format uses PBKDF2-HMAC-SHA256 with 100,000 iterations by default. This is an implementation parameter, not a general guarantee of resistance to offline password guessing. A future KDF upgrade requires versioned parameters and migration so existing files remain decryptable.

---

## Decision

### Cipher: AES-256-GCM

AES-256-GCM provides authenticated encryption: the 128-bit authentication tag is verified before plaintext is returned to callers. A random 96-bit nonce is generated per file using a cryptographically secure random number generator. The nonce is prepended to the ciphertext and stored with it.

The wire format for each encrypted file:
```
[12-byte nonce][16-byte GCM auth tag][ciphertext bytes]
```

### Key Derivation: PBKDF2

When the user enters a passphrase:
- A random 256-bit salt is generated once per connection configuration and stored with the encrypted config.
- PBKDF2-HMAC-SHA256 is applied with 100,000 iterations to derive a 256-bit master key.
- The master key is held in memory for the session and never written to disk.

PointyCastle implements the portable AES-GCM and PBKDF2 paths. Selected file-crypto paths use `cryptography`/`cryptography_flutter`, WebCrypto, Windows CNG or Linux OpenSSL. Provider metadata and key derivation still include Dart implementations; native acceleration does not establish an Apple-OS-only crypto build. See [the current inventory](../crypto-inventory.json).

### Architecture: `EncryptedStorageWrapper`

Rather than adding encryption logic to individual adapters, encryption is implemented as a `CloudStorageClient` decorator: `EncryptedStorageWrapper`. It wraps any adapter and intercepts `uploadFile`/`uploadStream` (encrypt before sending) and `downloadFileBytes`/`downloadStream` (decrypt after receiving).

This means encryption is available for all 11 providers without modifying any adapter code.

Capability flags `supportsSharing`, `supportsThumbnails`, and `supportsSearch` are forced to `false` on an encrypted wrapper, because these features require the server to interpret file contents — which it cannot do with ciphertext.

### Filename Encryption: Optional

Filenames are optionally encrypted using the same AES-256-GCM key, with the encrypted bytes encoded as a URL-safe base64 string. This adds a second layer of privacy but makes files unreadable through the provider's native web interface. It is offered as an opt-in toggle in the connection dialog.

### Key Management: BIP39 Mnemonic

The 256-bit master key is exportable as:
- A 64-character hex string (for technical users).
- A 24-word BIP39 mnemonic (the same standard used by hardware cryptocurrency wallets). BIP39 was chosen because it is a widely implemented, audited standard that converts 256 bits of entropy into a human-readable, error-correctable word list. Recovery from a mnemonic is deterministic.

The `KeyManagementDialog` offers export, import, and a verification step to confirm the user has written down the mnemonic before enabling encryption on a production connection.

---

## Consequences

**Positive:**

- The provider never sees plaintext file contents or (optionally) filenames. The threat model is fully addressed.
- Encryption works with any of the 11 providers with no per-provider code.
- AES-256-GCM with a per-file random nonce means two identical files produce different ciphertexts, preventing content deduplication attacks.
- The authenticated tag means CrispCloud detects corrupted or tampered ciphertexts before presenting garbage to the user.
- BIP39 mnemonics enable disaster recovery without requiring the user to manage a file.

**Negative / Trade-offs:**

- The client holds the key in memory. On mobile, the OS can evict the app; on reconnect, the user must re-enter the passphrase. App lock + biometric unlock mitigates friction.
- Encrypted filenames break the provider's web UI and mobile apps entirely — files appear as gibberish strings.
- The generic encrypted wrapper is not a Cryptomator vault filesystem. Separate format helpers now implement authenticated Cryptomator primitives; full vault file I/O remains outside that wrapper. See [the audit](../crypto-audit.md).
- Streaming transfers preserve the existing single-message GCM format. Decryption uses a private spool until the final authentication tag verifies; it does not release unauthenticated plaintext to the destination. This is distinct from a new independently authenticated chunk format.
- Key loss means permanent data loss. The BIP39 backup process is shown in the UI, but cannot be enforced.
