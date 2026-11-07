# Local TLS regression fixtures

These certificates and the **public, non-secret test private key** are used only
by loopback TLS tests. Never use them for a deployed service or real trust store.
No production certificate or credential is included.

- `ca.pem` is the test trust anchor; `other-ca.pem` has a different key/name.
- `server.pem` covers `localhost` and `127.0.0.1` and is signed by `ca.pem`.
- `wrong-host.pem` is signed by that CA but covers only `wrong.invalid`.
- `expired.pem` is signed by that CA but expired on 2021-01-01.
- `forged-issuer.pem` claims the same issuer name as `ca.pem`, but its signature
  was made with a different key. Matching a certificate's issuer text must never
  make it trusted.
- All leaf certificates share `server.key`. CA private keys are not stored.

The valid leaf certificates last one year, currently from 2026-11-06 through
2027-11-06. Renew them before that expiry. Apple rejects post-July-2019 TLS leaf
certificates whose lifetime exceeds 825 days, even if their current dates are
valid. These tests use an explicitly imported private trust anchor.
The test CA certificates last from 2020-01-01 through 2049-12-31.

They use RSA-2048 signatures with SHA-256, BasicConstraints, appropriate KeyUsage,
SubjectKeyIdentifier/AuthorityKeyIdentifier, and leaf
SubjectAlternativeName/ExtendedKeyUsage. Tests run without an external network
or a certificate-generation subprocess.

To renew, run `python3 test/fixtures/tls/generate.py` from the repository root in
an environment with Python's `cryptography` package installed. The script reuses
the public test server key and generates fresh in-memory CA keys; it does not
save any CA private key. Commit the six regenerated certificates together,
update the validity dates in this file, and run the TLS tests on all three
desktop platforms. The expired and forged fixtures remain invalid by design.

Apple's certificate requirements:

- https://support.apple.com/en-ie/103769
- https://support.apple.com/en-gb/102028
