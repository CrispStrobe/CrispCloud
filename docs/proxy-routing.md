# HTTP and SOCKS5 proxy routing

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
- **Bypass list:** comma-separated hostnames match themselves and subdomains.
  A leading dot is accepted, so `.example.com` matches `example.com` and
  `files.example.com`. IP addresses match exactly. `*` bypasses all hosts.

SOCKS5 is implemented directly from
[RFC 1928](https://www.rfc-editor.org/rfc/rfc1928) and
[RFC 1929](https://www.rfc-editor.org/rfc/rfc1929) with Dart's native socket APIs;
it adds no external package. If credentials are configured, the client offers
only password authentication. Each credential must contain 1–255 UTF-8 bytes.
SOCKS password authentication does not itself encrypt credentials on the
client-to-proxy connection.

## TLS and failure behavior

For HTTPS, TLS runs inside the SOCKS tunnel using the destination hostname and
the same configured trust anchors as direct HTTP clients. The native TLS engine
checks the chain, certificate validity and hostname. There is no certificate
accept-all callback.

Connect, SOCKS negotiation and TLS negotiation have a shared 30-second deadline,
or the HTTP client's configured connection timeout. Cancellation and timeout
close the underlying raw transport even while the TLS handshake is pending.
Handshake rejection, bad credentials, certificate errors and malformed replies
never fall back to HTTP proxying or a direct connection. Explicit bypass entries
are the only direct routes when SOCKS5 is selected.

Invalid saved settings remain blocked until corrected or explicitly disabled in
the proxy dialog. An unknown stored type is not treated as “No Proxy.” Invalid
environment settings are also blocked. Supported environment URL schemes are
`http`, `socks5`, `socks5h` and the legacy `socks` alias for SOCKS5. `HTTPS_PROXY`
selects the proxy for HTTPS destinations; a URL beginning with `https://` would
require TLS to the proxy itself and is not supported. SOCKS4, UDP association,
SOCKS BIND and proxy routing for direct FTP/SFTP/SMB are outside this increment.

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
