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
control/data session per transfer. Both paths use an owned native transport that
retains its TCP task and raw socket while TLS negotiation is pending.

Connection deadlines close the native transport even if the peer never answers
its TLS handshake. Closing a captured transfer session, disconnecting the
metadata client, or logging out closes their pending control/data connections.
An initial login is owned before authentication completes, so logout can also
cancel that handshake. A late native completion cannot revive a closed session.

## Scope

Passive FTP is supported in native builds. Servers must expose their passive
data ports through their firewall. [Verified download resume](ftp-resume.md)
negotiates `REST STREAM` for captured source identities and checks the complete
assembled file before publication. A server without the required restart or
source evidence refuses resume and requires a reviewed restart. Browser FTP,
FTP-specific proxies, FXP, upload resume and first-class SCP are separate gaps.

## Verification

The following focused tests use loopback sockets and the public test CA/key
fixtures under `test/fixtures/tls`; they need no provider credentials:

```sh
flutter test test/ftp_explicit_tls_test.dart test/ftp_security_mode_test.dart \
  test/ftp_transfer_session_test.dart test/ftp_transport_lifetime_test.dart \
  test/ftp_adapter_test.dart \
  test/ftp_config_service_test.dart test/widget/ftp_security_field_test.dart
```

They cover explicit and implicit TLS, control/data certificate rejection,
failed TLS negotiation, directory listings, bounded transfer bytes, legacy
mode/port preservation, malformed identity rejection and the localized mode
selector. Live interoperability with a user's server remains dependent on that
server's TLS and passive-port configuration.

The lifetime suite observes TCP EOF/reset at loopback peers that have received
ClientHello but never complete TLS. It covers explicit and implicit control
deadlines, session close, metadata disconnect, logout during initial connection,
and directory/upload/download data-channel deadlines and cancellation. The
observation occurs before fixture teardown, so a failed caller Future alone is
not treated as proof of transport cleanup.

The range-download API also owns its session before connection setup finishes.
Cancelling that subscription closes a pending control/data transport, including
an unanswered `REST` reply or data TLS handshake. The generic upload-stream API
does not expose a cancellation token before it subscribes to source bytes;
stopping a queued upload during that initial handshake can still wait for its
connection deadline. This does not claim immediate queue-stop propagation
through every provider API.

The final G37 gate passed all 145 tests across the lifetime, explicit-TLS,
streaming-session, adapter, media-transfer, provider-dispatch, SOCKS5, proxy and
TLS-verification suites. The 24 lifetime cases include observed peer closure,
failed upstream cancellation cleanup and closing an output sink after a
post-handshake receive timeout. Focused static analysis has no errors or warnings.
