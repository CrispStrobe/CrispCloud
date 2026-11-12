# HTTP and SOCKS proxy routing

The proxy setting applies to native Dart HTTP/HTTPS traffic, including cloud
storage requests that use those clients. Direct FTP, SFTP and SMB sockets do not
use this setting. Browser traffic follows browser/platform network settings.

## Supported routing

- **HTTP proxy:** native HTTP proxy requests and CONNECT tunnels for HTTPS
  destinations, with optional Basic proxy credentials. The connection to the
  proxy itself is ordinary HTTP.
- **SOCKS5:** a TCP CONNECT tunnel with either no authentication or username and
  password authentication. Destination names are sent to the proxy for DNS
  resolution. Literal IPv4 and IPv6 addresses use their corresponding SOCKS
  address types.
- **SOCKS4:** a TCP CONNECT tunnel to an IPv4 destination. Hostnames are resolved
  locally to an IPv4 address before contacting the proxy. An optional user ID
  identifies the client; it is not a password.
- **SOCKS4a:** the explicit remote DNS extension to SOCKS4. Destination hostnames
  are sent to the proxy without a local lookup. Literal IPv4 addresses use the
  ordinary SOCKS4 request. There is no automatic switch between these modes.
- **Bypass list:** comma-separated hostnames match themselves and subdomains.
  A leading dot is accepted, so `.example.com` matches `example.com` and
  `files.example.com`. IP addresses match exactly. `*` bypasses all hosts.

The implementations use Dart's native socket APIs and add no external package.
SOCKS5 follows
[RFC 1928](https://www.rfc-editor.org/rfc/rfc1928) and
[RFC 1929](https://www.rfc-editor.org/rfc/rfc1929). If credentials are configured, the client offers
only password authentication. Each credential must contain 1–255 UTF-8 bytes.
SOCKS password authentication does not itself encrypt credentials on the
client-to-proxy connection.

SOCKS4 and SOCKS4a follow the original
[SOCKS4 protocol](https://www.openssh.org/txt/socks4.protocol) and
[remote DNS extension](https://www.openssh.org/txt/socks4a.protocol).
Only CONNECT is implemented. The reply must have version 0 and success code 90;
rejection, identification failures, unsupported codes and truncated replies
close the connection. Destination addresses reserved for the remote DNS marker
(`0.0.0.x`, where `x` is nonzero) are rejected when supplied as literal targets.

For SOCKS4 modes, CrispCloud limits user IDs to 0–255 printable ASCII characters
and hostnames to their ASCII/IDNA form, at most 255 bytes. NUL/control characters,
IPv6 destination literals and passwords are not accepted. A saved SOCKS4
configuration containing a password remains invalid rather than silently
discarding the credential. Choosing a SOCKS4 mode in the settings dialog clears
the previous password and shows a user ID field with the mode's DNS behavior.

## TLS and failure behavior

For HTTPS, TLS runs inside the SOCKS tunnel using the destination hostname and
the same configured trust anchors as direct HTTP clients. The native TLS engine
checks the chain, certificate validity and hostname. There is no certificate
accept-all callback.

SOCKS4 local lookup, TCP connection, SOCKS negotiation and TLS negotiation share
a 30-second deadline, or the HTTP client's configured connection timeout.
Cancellation and timeout
close the underlying raw transport even while the TLS handshake is pending.
The platform's local DNS lookup cannot itself be canceled; a late result is
discarded and cannot open a new connection. Late native TCP tasks are canceled
and their eventual success or failure is observed.
Handshake rejection, bad credentials, certificate errors and malformed replies
never fall back to HTTP proxying or a direct connection. Explicit bypass entries
are the only direct routes when a SOCKS mode is selected. Closing an active
upload also releases its stream/sink after immediately closing the transport;
an upstream cleanup error does not replace the transfer's original failure.

Invalid saved settings remain blocked until corrected or explicitly disabled in
the proxy dialog. An unknown stored type is not treated as “No Proxy.” Invalid
environment settings are also blocked. Supported environment URL schemes are
`http`, `socks4`, `socks4a`, `socks5`, `socks5h` and the legacy `socks` alias for
SOCKS5. `socks4://user@host:1080` supplies an optional user ID; a password in that
URL is invalid. `socks4a://` explicitly selects remote DNS. `HTTPS_PROXY`
selects the proxy for HTTPS destinations; a URL beginning with `https://` would
require TLS to the proxy itself and is not supported. UDP association,
SOCKS BIND and proxy routing for direct FTP/SFTP/SMB are outside this setting.

Proxy hosts must be DNS/IDNA names or literal IPv4/IPv6 addresses, with the port
provided separately. URLs, embedded credentials, control characters and native
proxy directive separators are rejected before creating a client. This also
prevents a restored HTTP host from adding a direct fallback route.
The character check runs before native IP parsing: a valid IPv4/IPv6 prefix
followed by an embedded NUL cannot bypass validation or preserve hidden suffixes.

## Verification

`test/socks5_proxy_test.dart` runs against a real loopback SOCKS server and local
HTTP/HTTPS origins. It covers fragmented replies, authenticated and unauthenticated
tunnels, remote DNS, IPv4/IPv6 address encoding, keep-alive, a multi-chunk 2 MiB
upload/download with paused reads, coalesced first payload bytes, invalid
certificates and hostnames, refusal without fallback, cancellation and timeout
during SOCKS and TLS negotiation, bypass behavior, and invalid stored settings.

`test/support/socks5_fixture.dart` observes the TLS ClientHello in cancellation
tests and peer closure after timeouts, so completing a failed request alone does
not count as a successful cleanup test.

`test/socks4_proxy_test.dart` uses an independent loopback SOCKS4/4a fixture and
local HTTP/HTTPS origins. It covers local IPv4 lookup versus remote DNS, literal
addresses, user ID validation, fragmented and coalesced replies, keep-alive,
2 MiB streamed transfers with paused reads, rejected/truncated replies, strict
certificate and hostname verification, explicit bypasses, mode persistence and
invalid restored/environment credentials. Stalled SOCKS/TLS tests observe peer
closure, and delayed lookup tests prove that cancellation and timeout prevent
late TCP connections. The existing SOCKS5 suite is the shared transport
regression gate, including active upload cancellation and sink completion.

The final six-suite gate passed 197 tests, including the embedded-NUL host guard
and exact regression cases. Focused analysis and independent review are clean.
Native HTTP/HTTPS routing is the verified scope; live-server and platform
acceptance remain separately recorded in the gap checkpoint ledger.
