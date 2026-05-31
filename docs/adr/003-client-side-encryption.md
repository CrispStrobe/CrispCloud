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

**AES-128-CBC** was rejected: 128-bit keys are not future-proof, and CBC without explicit authentication is vulnerable to padding oracle attacks. An authenticated cipher is required.

**ChaCha20-Poly1305** was considered. It is excellent (used in TLS 1.3, WireGuard) but AES-256-GCM is more widely understood, more universally supported in hardware (AES-NI), and the `cryptography` package exposes it through OS-accelerated implementations on all platforms.

**Argon2id** and **scrypt** are memory-hard KDFs better suited to password hashing. PBKDF2 with a high iteration count (100,000) is the NIST-recommended approach for key derivation and is universally supported. The threat model here is offline brute-force of the passphrase given the encrypted ciphertext — PBKDF2 with 100K iterations provides adequate resistance for passphrases of reasonable length.

---

## Decision

### Cipher: AES-256-GCM

AES-256-GCM provides authenticated encryption: the 128-bit authentication tag detects any tampering with the ciphertext before decryption begins. A random 96-bit nonce is generated per file using a cryptographically secure random number generator. The nonce is prepended to the ciphertext and stored with it.

The wire format for each encrypted file:
```
[12-byte nonce][16-byte GCM auth tag][ciphertext bytes]
```

### Key Derivation: PBKDF2

When the user enters a passphrase:
- A random 256-bit salt is generated once per connection configuration and stored with the encrypted config.
- PBKDF2-HMAC-SHA256 is applied with 100,000 iterations to derive a 256-bit master key.
- The master key is held in memory for the session and never written to disk.

The `cryptography` package (`pub.dev/packages/cryptography`) is used for all primitives. It delegates to OS-level crypto libraries on each platform: CryptoKit on macOS/iOS, BouncyCastle on Android, OS CNG on Windows. This provides hardware-accelerated AES on any platform with AES-NI.

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
- There is no compatibility with Cryptomator vault format (a future goal). A user who also uses Cryptomator Desktop cannot share the same encrypted folder.
- Streaming encryption (chunking a large file into individually encrypted segments) is not yet implemented. Currently, the entire file is buffered in memory for encryption. This is a memory concern for very large files and is tracked as a future improvement.
- Key loss means permanent data loss. The BIP39 backup process is shown in the UI, but cannot be enforced.
