# FTP runtime provenance

This directory contains the runtime source and package metadata from
`ftpconnect` 2.0.10, distributed under the MIT license. The original copyright
notice and license are retained in `LICENSE`.

- Upstream repository: https://github.com/salim-lachdhaf/dartFTP
- Package release: https://pub.dev/packages/ftpconnect/versions/2.0.10
- Source: the published 2.0.10 package, matching the repository's previous lock.
  Published archive SHA-256: `a9ebac24a50b17dc9a1101fff85c3729fd8c16ec41346b0fa6e549616e23b2f6`.

Local changes retain the public FTP API and harden TLS behavior:

- Validate certificates and hostnames on implicit and explicit TLS connections.
- Require `AUTH TLS` with reply 234; never fall back to another security mode.
- Require successful `PBSZ 0` and `PROT P` negotiation.
- Protect passive directory, upload and download data sockets with TLS whenever
  the control connection uses TLS.
- Accept an optional `SecurityContext` so tests and embedding applications can
  supply trust anchors without disabling certificate checks.
- Remove obsolete `final` parameter modifiers rejected by the current Dart SDK.
- Reject command-injection characters and redact authentication commands in logs.

The app retains its separately bounded streaming data-transfer implementation.
Local loopback tests exercise both runtime paths, certificate failures, TLS
negotiation refusal and ordinary FTP compatibility. TLS follows RFC 4217:
https://www.rfc-editor.org/rfc/rfc4217
