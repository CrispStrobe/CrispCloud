# Provider setup

Choose **Connect** and select a provider. The connection dialog is the
authoritative list for your build. Capabilities differ: a provider that can copy
does not automatically support sharing, permissions, native moves or resumable
uploads.

Detailed historical provider notes are preserved in the
[provider setup archive](provider-setup-details.md).

## Credentials at a glance

| Provider | Main fields | Notes |
| --- | --- | --- |
| **Filen** | Email, password, optional 2FA | Native E2E encryption; limited versioning/share/thumbnails |
| **Internxt** | Email, password | E2E encrypted; transfers may buffer in memory |
| **SFTP** | Host, port, user, password or key | Native streaming; host-key verification |
| **WebDAV** | URL, user, password | Use the exact collection URL; TLS strongly preferred |
| **SMB** | Host, share, domain/user, password | SMB2/3; signed connections |
| **S3** | Endpoint, region, bucket, key/secret | Presigned URLs; SSE and storage-class options |
| **FTP/FTPS** | Host, port, user, password, mode | Choose explicit/implicit TLS deliberately |
| **Google Drive** | OAuth sign-in | Shared drives, versions, Google Docs export |
| **OneDrive/SharePoint** | OAuth sign-in | Graph API, sites and drives |
| **Dropbox** | OAuth sign-in | Shared folders, content hash, Paper export |
| **Nextcloud** | URL, user, app password | Chunked upload v2 and ETag tracking |
| **pCloud** | Email/user, password | Standard transfers; region-specific hosts |
| **Azure Blob** | Account, container, SAS or key | SAS scopes and expiry must be valid |
| **Backblaze B2** | Key ID/application key or S3 mode | Native and S3-compatible paths |
| **Hetzner Storage Box** | Host, user, password/key | SFTP/WebDAV/FTP depending on plan |

Additional accounts exposed by the picker may be session-only. Save/restart
behavior follows the credential store selected in Settings.

## General setup

1. Create the account or app password at the provider.
2. Prefer an app-specific password over your primary password.
3. Enable 2FA where offered; Filen asks for the code only when required.
4. Grant the narrowest folder/scope the provider allows.
5. Test with a small folder before starting a large transfer.
6. For OAuth providers, complete the browser sign-in and return to CrispCloud.

## SFTP and SSH

- Accept the host key only after checking its fingerprint.
- Password, key file and local SSH agent authentication are supported.
- Private keys are used only for the connection; they are not copied into logs.
- Jump hosts and SSH agent forwarding are configured in the terminal/SSH
  profile, not the generic file-provider form.

## WebDAV and Nextcloud

- Use the full collection URL, including any provider-specific path.
- Nextcloud app passwords are preferred over the account password.
- Self-signed certificates require an explicit platform trust decision; do not
  disable verification casually.

## S3-compatible storage

- Confirm endpoint, region and path-style vs virtual-hosted addressing.
- Restrict the access key to the required bucket/prefix.
- Browser builds need CORS for the bucket.
- Presigned URLs have an expiry; a stale URL fails without retry loops.

## FTP/FTPS

- Explicit TLS secures the control connection before login.
- Implicit TLS starts before the greeting.
- Secure modes protect passive data connections and validate certificates.
- Failed TLS negotiation stops the connection.
- FTP download resume needs server restart support and a verified original file;
  upload resume is unavailable.

## Google Drive, OneDrive and Dropbox

These use OAuth. CrispCloud requests the scopes needed for file operations;
revoke access from the provider’s account page if a token is lost.

Provider-specific limits:

- Google Docs/Sheets/Slides are exported copies, not editable native files.
- OneDrive/SharePoint may expose multiple drives or site libraries.
- Dropbox Paper is exported; it is not a native editable document.

## Azure Blob and B2

- Azure SAS tokens need the correct container, permissions and expiry.
- Account-key mode is more powerful; prefer a narrow SAS.
- B2 supports native and S3-compatible configuration. Do not mix keys from
  different modes.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Authentication fails | App password, 2FA, clock skew, token expiry |
| Folder opens but upload fails | Write scope, bucket policy, CORS, quota |
| TLS/certificate error | Correct hostname, trusted CA, explicit FTPS mode |
| Transfer stalls | Provider throttling, proxy, large-file limit, retry policy |
| Account disappears after restart | Selected credential store and saved-account support |
| OAuth loops | Popup blocked, redirect URI, provider session, revoked consent |

## Security

- Credentials stay in the selected credential store.
- Error messages identify the failed operation without printing secrets.
- Remote paths are never treated as local paths.
- A saved account does not grant filesystem access or external process launch.
- Provider sharing/permissions are not implied by copy support.
