# Verified FTP download resume

Native FTP downloads now have a server-negotiated byte-offset read path. A
reviewed **Resume verified** operation, or recovery of a journal-owned local
partial file, can request the remainder using `REST` followed by `RETR`.
The existing local bytes are copied into a new private stage; the original
partial file or existing destination is not opened for append.

This implementation covers plain FTP, implicit FTPS and explicit FTPES. It
requires a server that advertises `REST STREAM` and supplies consistent `SIZE`
and `MDTM` evidence. No live server interoperability is certified by loopback
tests. Upload resume and server-to-server transfer remain separate work.

## Evidence required before resuming

FTP listings retain an opaque `rangeReadSnapshot` containing:

- A SHA-256 identity derived from the endpoint, port, account, security mode
  and root. It contains no password, token or transport grant.
- The exact absolute remote path, original byte size and modification time.

The security mode is also part of the persistent storage namespace. A saved
plain connection cannot silently bind to a secure connection, or vice versa,
merely because the hostname and port match. Changing the account, endpoint,
port or source path invalidates captured range evidence.

`rangeReadSnapshot` is deliberately **not** an immutable provider revision.
The transfer journal continues to record a complete SHA-256 digest of the
original source. Recovery verifies that digest against the reconnected source
and compares the retained local bytes with the source prefix. Direct conflict
resume captures the same complete source digest before writing if no durable
digest is already available. The assembled prefix and resumed suffix must
match that digest before the temporary file can become the destination.

These checks address a server that ignores the requested offset, returns
incorrect bytes of the expected length, or changes content without changing
its size or timestamp. A server's positive `REST` response is not treated as
proof that the returned bytes came from the requested offset.

All reads used to verify the source still transfer data through the client.
In particular, the full source digest and prefix verification can require
additional complete or partial downloads. Resume avoids starting the actual
copy pass from byte zero; this implementation does not promise an overall
bandwidth reduction compared with a fresh copy.

## Protocol sequence and range contract

The independent bounded transfer session keeps its usual TLS and login setup,
then selects binary representation with `TYPE I`. A resumed read follows this
sequence:

1. Require a successful `FEAT` reply containing exactly `REST STREAM`, ignoring
   letter case. Missing, malformed or refused support is an unsupported resume
   result, without a fallback download.
2. Select `MODE S` and `STRU F`. Read `SIZE` and `MDTM`; compare them with the
   captured source evidence.
3. Negotiate `EPSV`, with the existing `PASV` fallback, and connect the data
   socket to the control connection's peer address.
4. Send `REST <offset>`, require reply `350`, and send `RETR <path>` immediately
   afterward. No metadata, passive-mode or navigation command intervenes.
5. Verify the remaining wire byte count, accept a successful completion reply,
   and read `SIZE` and `MDTM` again before completing the stream.

RFC 3659 defines the restart number as an octet offset in stream mode and
requires `REST` immediately before the transfer command. The restart reply
acknowledges the marker; the following transfer command can still reject it.
Its `REST STREAM` feature line distinguishes stream restart from support for
other transfer modes. See [RFC 3659, sections 5.1–5.4](https://www.rfc-editor.org/rfc/rfc3659.html#section-5).

The `readTransferRange(path, offset, length: n)` contract returns the half-open
interval **`[offset, offset + n)`**. An omitted length reads to EOF. Negative
offsets or lengths, offsets past EOF and ranges extending past the captured
size fail before restart negotiation. An empty range is validated against the
source metadata and opens no data connection.

FTP does not provide an end offset in this command sequence. For a bounded
range, the session emits only the selected bytes, then drains and validates
the remaining suffix and completion reply. Cancelling instead of waiting for
stream completion does not establish a verified range result. The transfer
consumer keeps all emitted bytes provisional until the stream completes and
the complete-file digest succeeds.

`SIZE` and `MDTM` responses must have valid single-line numeric/time syntax.
Modification times are UTC calendar fields; supplied fractional precision is
retained by the protocol parser. The listing library represents those fields
as a `DateTime` without its UTC marker, so the adapter compares calendar fields
without applying the computer's timezone. Missing timestamps, inconsistent
listing/`MDTM` precision or dates that cannot be represented faithfully refuse
resume. They do not disable ordinary full downloads. The original-server-time
comparison follows [RFC 3659, sections 2.3 and 3](https://www.rfc-editor.org/rfc/rfc3659.html#section-3).

## Durable partial files and publication

The native writer retains an interrupted stage only when the journaled runner
explicitly requests it for a persistent, recoverable job and the private
staging path has already been recorded by the durable checkpoint. A retained
stage must be a nonempty regular streamed file no larger than the expected
source. Ordinary writes without that recovery ownership keep their cleanup
behavior.

The stage is **candidate recovery data**, not a trusted prefix merely because
its path appears in the journal. Recovery reopens the original source and
destination identities, checks the saved full source digest, and verifies the
stage's current bytes before selecting its length as the restart offset.
Execution verifies the prefix again. It then constructs a fresh stage from
that prefix plus the negotiated remote suffix and checks the assembled digest
before publication.

Incorrect prefixes, remote mutation, refused offsets, short reads, failed
completion replies and interrupted reconnection cannot replace the previous
verified destination. They remain reviewable failures. A complete restart is
an explicit recovery/conflict decision. No failure silently changes a resume
operation into an append or a new full download.

## Connection ownership and TLS

Every read owns one control session and its passive data transport. The native
transport retains pending TCP and raw TLS sockets. Range subscription
cancellation closes those transports immediately, including while awaiting
`REST` or a stalled data TLS handshake. Adapter range reads capture that owner
before awaiting connection setup. Logout and account replacement also close
active and pending owned sessions; a late completion cannot revive them.

The established certificate policy is unchanged. Explicit TLS requires
`AUTH TLS` before credentials. Secure modes require `PBSZ 0` and `PROT P`, and
both control and data channels validate the configured hostname and certificate
chain. There is no certificate bypass or plaintext fallback. The passive
address comes from the control peer; a different host embedded in `PASV` is
ignored. See [RFC 4217](https://www.rfc-editor.org/rfc/rfc4217.html) for FTP TLS
negotiation and [RFC 2428, section 3](https://www.rfc-editor.org/rfc/rfc2428.html#section-3)
for extended passive addressing.

## Verification and remaining acceptance

`test/support/ftp_resume_fixture.dart` is an independent socket peer. It parses
commands and applies restart offsets itself; it does not reuse production
reply or transfer helpers. Secure tests use the repository's public loopback
CA and server keys under `test/fixtures/tls`.

The focused test command is:

```sh
flutter test test/ftp_resume_test.dart test/ftp_transfer_session_test.dart \
  test/ftp_explicit_tls_test.dart test/ftp_transport_lifetime_test.dart \
  test/ftp_adapter_test.dart test/file_operation_service_test.dart \
  test/file_operation_backend_test.dart test/transfer_recovery_test.dart
```

The added cases cover exact wire ordering and binary bytes in all three modes;
exclusive range bounds and empty ranges; absent capabilities, invalid replies
and unavailable metadata; endpoint/account/mode mismatch; source mutation;
wrong offsets, short reads and failed final replies; strict data certificates;
observed peer closure during cancellation; direct conflict resume with wrong
prefixes and wrong same-length suffixes; persisted snapshot evidence; and an
actual cancelled local write that is recovered after reconnecting the original
FTP account.

Live acceptance remains open. Record each tested server and version, operating
system, selected security mode, passive-port configuration, relevant feature
and metadata responses, exact successful offset, and the outcome of interrupted
reconnection. Servers requiring TLS data-session reuse need separate live
validation; the native transport does not add a TLS session-reuse guarantee.
No upload capability is inferred from `REST STREAM`: resumed `STOR`, `APPE`,
truncate behavior and upload completion evidence are not implemented here.

No new dependency was added. Restart, snapshot and lifetime code is owned by
this project; hashing uses the existing `crypto` dependency. The existing
MIT-licensed FTP metadata runtime remains documented in
`packages/ftpconnect/UPSTREAM.md`.
