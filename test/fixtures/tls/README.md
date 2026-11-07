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

The non-expired certificates are valid from 2020-01-01 through 2049-12-31.
They use RSA-2048 signatures with SHA-256, BasicConstraints, appropriate KeyUsage
and leaf SubjectAlternativeName/ExtendedKeyUsage. Tests run without an external
network or a certificate-generation subprocess.
