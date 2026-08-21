# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's
private vulnerability reporting for this repository, or contact the maintainer
through the private address listed on the repository profile. Include the
affected platform and version, reproduction steps, and whether credentials or
unencrypted file content may have been exposed.

You should receive an acknowledgement within seven days. Please allow time for
a coordinated release before publishing details.

## Supported versions

Security fixes target the latest released version and the current `main`
branch. Older builds should be upgraded because provider APIs and native
dependencies change independently of CrispCloud.

## Scope

Credential storage, encryption/decryption, provider authentication, local REST
API authorization, archive extraction, sandbox escapes, and unintended
telemetry or path disclosure are in scope. Provider outages and vulnerabilities
in a provider's own service should be reported to that provider.

See [docs/SECURITY_ARCHITECTURE.md](docs/SECURITY_ARCHITECTURE.md) for the threat
model and data-flow guarantees.
