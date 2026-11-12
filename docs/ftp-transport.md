# FTP connections

The installed app offers three connection modes. New FTP connections select
explicit TLS; changing a mode updates the conventional port only when the port
field was empty or still held the previous mode's default. A custom port is
retained.

| Mode | Usual port | Control connection | File and directory data |
| --- | --- | --- | --- |
| Explicit TLS (FTPES) | 21 | Greeting, `AUTH TLS`, verified TLS, then login | Verified TLS after `PBSZ 0` and `PROT P` |
| Implicit TLS (FTPS) | 990 | Verified TLS before the greeting | Verified TLS after `PBSZ 0` and `PROT P` |
| Plain FTP | 21 | Unencrypted | Unencrypted |

Saved connections and connection profiles record the mode explicitly. Existing
`useTLS=true` credentials and `tls=true` profiles retain **implicit** TLS and
their saved port. An unknown mode is rejected; it never becomes unencrypted
FTP. Invalid profiles require choosing a valid mode or another profile.

## TLS behavior

Explicit TLS requires reply 234 to `AUTH TLS` before credentials are sent. A
refusal, wrong hostname, untrusted/expired certificate, or failed handshake ends
the connection. There is no fallback to `AUTH SSL` or unencrypted FTP. Private
data protection requires successful `PBSZ 0` and `PROT P` replies; directory
listings, downloads and uploads use the same hostname and trust policy.

FTP uses the platform/Dart trusted roots. The custom CA setting for HTTP clients
does not currently change FTP's trust store. Administrators using a private CA
must make it available in the native trust configuration supported by their
platform. No certificate-verification bypass is offered.

The small MIT-licensed FTP metadata runtime is preserved under
`packages/ftpconnect`. Its source/version/license and local certificate/data
protection fixes are recorded in that package's `UPSTREAM.md`. The app's
bounded streaming transfer implementation remains independent and uses one
control/data session per transfer.

## Scope

Passive FTP is supported in native builds. Servers must expose their passive
data ports through their firewall. Browser FTP, FTP-specific proxies, FXP,
byte-range FTP resume and first-class SCP are separate gaps. The general
reviewed transfer queue, pause/cancel and recovery controls still apply to FTP
jobs, but recovery does not imply a server supports restarting a data stream at
an arbitrary byte offset.

## Verification

The following focused tests use loopback sockets and the public test CA/key
fixtures under `test/fixtures/tls`; they need no provider credentials:

```sh
flutter test test/ftp_explicit_tls_test.dart test/ftp_security_mode_test.dart \
  test/ftp_transfer_session_test.dart test/ftp_adapter_test.dart \
  test/ftp_config_service_test.dart test/widget/ftp_security_field_test.dart
```

They cover explicit and implicit TLS, control/data certificate rejection,
failed TLS negotiation, directory listings, bounded transfer bytes, legacy
mode/port preservation, malformed identity rejection and the localized mode
selector. Live interoperability with a user's server remains dependent on that
server's TLS and passive-port configuration.

TLS-upgrade calls have a caller-side timeout. The FTP tests establish certificate
and data-protection behavior and cancellation of an established transfer;
cleanup of a transport stalled inside a TLS upgrade remains outside this
verification coverage.
