# Provider Setup Guide

This guide covers how to configure each of CrispCloud's 11 providers: what credentials are needed, where to find them, and common troubleshooting steps.

---

## Table of Contents

1. [Filen](#filen)
2. [Internxt](#internxt)
3. [SFTP](#sftp)
4. [WebDAV](#webdav)
5. [Amazon S3 and S3-Compatible Storage](#amazon-s3-and-s3-compatible-storage)
6. [FTP / FTPS](#ftp--ftps)
7. [Google Drive](#google-drive)
8. [OneDrive](#onedrive)
9. [Dropbox](#dropbox)
10. [Nextcloud](#nextcloud)
11. [pCloud](#pcloud)
12. [Troubleshooting](#troubleshooting)

---

## Filen

Filen is an end-to-end encrypted cloud storage provider. CrispCloud connects using your Filen account credentials directly — no API key is needed.

### Sign Up

1. Go to [filen.io](https://filen.io) and create a free account.
2. Verify your email address.

### Connection Dialog Fields

| Field | Value |
|-------|-------|
| Email | Your Filen account email |
| Password | Your Filen account password |
| Two-Factor Code | Required only if 2FA is enabled on your account |

CrispCloud detects whether 2FA is required and prompts for the code automatically.

### Notes

- Filen uses client-side encryption natively. Files are encrypted at the Filen SDK level before upload. CrispCloud's own encryption layer is additional to Filen's.
- Filen does not support versioning, share links, or provider-native thumbnails via the CrispCloud adapter.

---

## Internxt

Internxt is an open-source, end-to-end encrypted cloud storage provider. Connection uses your Internxt account credentials.

### Sign Up

1. Go to [internxt.com](https://internxt.com) and create a free account.
2. Verify your email address.

### Connection Dialog Fields

| Field | Value |
|-------|-------|
| Email | Your Internxt account email |
| Password | Your Internxt account password |

### Notes

- Internxt does not support streaming transfers in the current adapter. Files are buffered in memory during transfer.
- The Internxt adapter can be disabled at compile time with the `isInternxtSupported = false` flag in `cloud_storage_interface.dart`.

---

## SFTP

SFTP (SSH File Transfer Protocol) connects to any SSH server. It is the most capable protocol for self-hosted storage.

### Connection Dialog Fields

| Field | Value |
|-------|-------|
| Hostname | IP address or domain name of the SSH server |
| Port | Default: 22 |
| Username | SSH username |
| Password | SSH password |
| SSH private key | Select an OpenSSH, PKCS#1 RSA or SEC1 EC private key file |
| Key passphrase | Passphrase for an encrypted private key, if applicable |

The connection dialog supports password authentication, including a single
unambiguous keyboard-interactive password prompt, or an SSH private key. For
key authentication, select **SSH private key**, choose the key file, and enter
its passphrase if encrypted. The key and passphrase are stored in the app's
secure credential store to reconnect. On the web, SFTP requires an SSH-over-
WebSocket bridge. Interactive one-time-password challenges and combinations
of multiple SSH authentication factors are not currently supported.

### Known Hosts

CrispCloud stores the server's host key fingerprint on first connection and verifies it on subsequent connections. If the host key changes unexpectedly, the connection is refused — a security protection against MITM attacks.

### Notes

- SFTP is the only provider with native streaming transfers (32 KB chunks, no full-file buffering).
- SFTP is the only provider with a chmod/chown permissions editor.
- Symbolic links are detected and shown with a link indicator.

---

## WebDAV

WebDAV works with ownCloud, Seafile, Nextcloud (legacy), nginx WebDAV module, Apache mod_dav, and many other servers.

### Connection Dialog Fields

| Field | Value |
|-------|-------|
| URL | Full WebDAV endpoint URL (see below) |
| Username | WebDAV username |
| Password | WebDAV password |

### Common WebDAV URLs

| Service | URL Pattern |
|---------|-------------|
| ownCloud | `https://yourserver.com/remote.php/dav/files/USERNAME/` |
| Seafile | `https://yourserver.com/seafdav/` |
| Generic WebDAV | `https://yourserver.com/webdav/` |
| nginx mod_dav | `https://yourserver.com/dav/` |
| Nextcloud (WebDAV) | `https://yourserver.com/remote.php/dav/files/USERNAME/` (prefer the Nextcloud provider instead) |

### Notes

- WebDAV does not support streaming, versioning, or sharing in CrispCloud.
- If your server uses a self-signed TLS certificate, import the CA certificate in **Settings → Network → Custom CAs**.
- For Nextcloud, use the dedicated Nextcloud provider (below) instead of WebDAV to get sharing support.

---

## Amazon S3 and S3-Compatible Storage

CrispCloud supports Amazon S3 and any S3-compatible service using pure Dart SigV4 signing.

### Amazon S3 Setup

1. Log in to the [AWS Console](https://console.aws.amazon.com).
2. Create an IAM user with programmatic access and attach a policy granting `s3:*` on your bucket.
3. Save the **Access Key ID** and **Secret Access Key**.
4. Note your **bucket name** and **region** (e.g., `us-east-1`).

### S3 Connection Dialog Fields

| Field | Value |
|-------|-------|
| Access Key ID | AWS access key ID |
| Secret Access Key | AWS secret access key |
| Region | AWS region (e.g., `us-east-1`) |
| Bucket | Bucket name |
| Endpoint | Leave blank for AWS; set for S3-compatible services (see below) |
| Path Style | Enable for MinIO and some other services |

### S3-Compatible Endpoints

| Service | Endpoint |
|---------|----------|
| MinIO (self-hosted) | `http://your-minio-server:9000` |
| Backblaze B2 | `https://s3.us-west-002.backblazeb2.com` (use your region) |
| Wasabi | `https://s3.wasabisys.com` |
| DigitalOcean Spaces | `https://nyc3.digitaloceanspaces.com` (use your region) |
| Cloudflare R2 | `https://<account-id>.r2.cloudflarestorage.com` |

For Backblaze B2, the bucket name and application key ID / application key map to Access Key ID / Secret Access Key.

For Cloudflare R2, create an API token in the R2 section of the Cloudflare dashboard with **Object Read & Write** permissions.

### CORS Configuration (Web PWA only)

If you are using CrispCloud as a PWA in a browser, you must configure CORS on your S3 bucket:

```json
[
  {
    "AllowedHeaders": ["*"],
    "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
    "AllowedOrigins": ["https://your-crispcloud-domain.com"],
    "ExposeHeaders": ["ETag"]
  }
]
```

Apply this via the AWS Console (Bucket → Permissions → CORS) or with the AWS CLI:

```bash
aws s3api put-bucket-cors --bucket my-bucket --cors-configuration file://cors.json
```

### Notes

- Files larger than 5 MB are automatically uploaded using the S3 multipart API, with per-part progress reporting.
- Interrupted multipart uploads can be resumed.
- Virtual-hosted style (`bucket.s3.region.amazonaws.com`) is used by default; path style (`endpoint/bucket`) is used when **Path Style** is enabled.

---

## FTP / FTPS

The installed app supports plain FTP, explicit TLS (FTPES) and implicit TLS
(FTPS), with passive data connections.

### Connection Dialog Fields

| Field | Value |
|-------|-------|
| Hostname | FTP server hostname or IP |
| Port | Usually 21 for FTP/FTPES, 990 for implicit FTPS; custom ports are retained |
| Username | FTP username |
| Password | FTP password |
| Connection security | Explicit TLS (FTPES), implicit TLS (FTPS), or unencrypted FTP |

### Notes

- Plain FTP sends credentials in cleartext. Use FTPS wherever possible.
- New connections default to explicit TLS: the app requests `AUTH TLS` before
  sending credentials. Refusal or a failed handshake stops the connection.
- Existing saved TLS connections keep their implicit TLS mode and saved port.
- TLS validates the server certificate and hostname on control **and** data
  connections, including directory listings. `PBSZ 0` and `PROT P` must succeed.
- Native bounded streaming transfers are supported. FTP does not provide app
  version history, native sharing, byte-range resume or FXP.
- FTP is unavailable in the browser and is not routed through the app's HTTP
  proxy. FTP uses the operating system/Dart trust roots; imported custom CAs in
  HTTP settings do not change the FTP trust store.

See [FTP transport behavior and verification](ftp-transport.md).

---

## Google Drive

CrispCloud connects to Google Drive via OAuth2. No API key is required — authentication uses CrispCloud's bundled OAuth2 client ID and opens a browser window for the Google sign-in flow.

### Authentication Flow

1. In the connection dialog, select **Google Drive** and click **Connect**.
2. A browser window opens to Google's OAuth2 authorization page.
3. Sign in with your Google account and grant CrispCloud read/write access to Google Drive.
4. The browser redirects back to CrispCloud and the connection completes.

The OAuth2 token is stored securely in your OS keychain and refreshed automatically. You will not need to re-authenticate unless you revoke access or the refresh token expires.

### Notes

- Google Drive supports versioning (view and restore previous file versions), sharing (with permission controls), full-text content search, and provider-native thumbnails.
- Path resolution uses Google Drive's ID-based API internally, with a client-side path-to-ID cache.
- Large files use the multipart upload API for progress reporting.
- Shared drives (Team Drives) are not yet supported in the current adapter.

### Revoking Access

Go to [myaccount.google.com/permissions](https://myaccount.google.com/permissions) and remove CrispCloud to revoke the OAuth2 token.

---

## OneDrive

CrispCloud connects to OneDrive and SharePoint via the Microsoft Graph API v1.0 with OAuth2 authentication. No API key or MSAL SDK is required.

### Authentication Flow

1. In the connection dialog, select **OneDrive** and click **Connect**.
2. A browser window opens to Microsoft's login page.
3. Sign in with your Microsoft account (personal OneDrive or work/school account).
4. Grant CrispCloud permission to access your files.
5. The browser redirects back to CrispCloud.

### Notes

- OneDrive supports versioning, sharing with expiry dates, and full-text content search via Microsoft Graph.
- Share links can be password-protected and set to expire on a specific date.
- SharePoint shared libraries are not yet supported.

### Revoking Access

Go to [account.microsoft.com/privacy/app-access](https://account.microsoft.com/privacy/app-access) and remove CrispCloud.

---

## Dropbox

CrispCloud connects to Dropbox via the Dropbox API v2 with OAuth2 authentication.

### Authentication Flow

1. In the connection dialog, select **Dropbox** and click **Connect**.
2. A browser window opens to Dropbox's authorization page.
3. Sign in and click **Allow**.
4. The browser redirects back to CrispCloud.

### Notes

- Dropbox supports versioning, sharing with password protection and expiry dates, and full-text content search.
- Dropbox share links support password protection.
- Paginated listing is used for directories with many files.
- Shared folders and Dropbox Paper documents are not yet supported.

### Revoking Access

Go to [dropbox.com/account/connected-apps](https://www.dropbox.com/account/connected-apps) and disconnect CrispCloud.

---

## Nextcloud

Nextcloud is an open-source self-hosted cloud platform. CrispCloud connects via WebDAV for file access and the OCS API for sharing features.

### Connection Dialog Fields

| Field | Value |
|-------|-------|
| Server URL | `https://your-nextcloud-server.com` |
| Username | Your Nextcloud username |
| Password | App password (recommended) or account password |

### Browser access (Web/PWA)

Desktop access succeeding does not establish browser access: browsers enforce CORS,
TLS trust and mixed-content restrictions. Enter the installation root, including
any subdirectory (for example `https://cloud.example/nextcloud`), not the full DAV
endpoint. The browser error now identifies the exact DAV endpoint and app origin.

For a cross-origin deployment, the server administrator must allow the **exact
CrispCloud origin** on the DAV route. Handle the unauthenticated `OPTIONS`
preflight and permit `PROPFIND` plus the `Authorization`, `Depth` and
`Content-Type` request headers. File operations additionally need the methods
and headers they use, such as `PUT`, `MKCOL`, `COPY`, `MOVE`, `DELETE`,
`Destination`, `Overwrite`, `If-Match` and `Range`; expose response metadata such
as `ETag`, `Content-Range` and `Accept-Ranges`. Keep normal DAV authentication
for actual requests. Do not solve this by disabling authentication or using an
untrusted public CORS proxy.

An HTTPS-hosted app needs an HTTPS Nextcloud URL and a certificate trusted by
the browser. App custom-CA settings cannot override browser certificate policy.
Inspect the browser Network/Console for the precise blocked request; JavaScript
only receives an opaque failure for these cases and cannot determine which
restriction caused it. Use a native CrispCloud app or host the app on the same
origin if the server cannot permit cross-origin DAV.

References: [Nextcloud WebDAV access](https://docs.nextcloud.com/server/stable/user_manual/en/files/access_webdav.html)
and [browser CORS behavior](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS).

### Generating an App Password (Recommended)

Using an app password is strongly recommended over your main account password:

1. Log in to your Nextcloud web interface.
2. Go to **Profile (top right) → Settings → Security**.
3. Under **App passwords**, enter a name (e.g., "CrispCloud") and click **Create new app password**.
4. Copy the generated password — it is shown only once.
5. Use this password in CrispCloud's connection dialog.

App passwords can be revoked individually without changing your main account password.

### Self-Signed Certificates

If your Nextcloud server uses a self-signed TLS certificate:
1. Export the CA certificate (or the server certificate if self-signed) in PEM format.
2. In CrispCloud, go to **Settings → Network → Custom CAs** and import the file.

### Notes

- The Nextcloud provider supports sharing via the OCS Share API.
- The adapter supports version history and bounded streaming. Search support depends on the server APIs.
- The WebDAV endpoint is derived automatically from the server URL (`/remote.php/dav/files/USERNAME/`).

---

## pCloud

pCloud is a cloud storage provider with European and US server options. CrispCloud connects via OAuth2.

### Authentication Flow

1. In the connection dialog, select **pCloud** and click **Connect**.
2. A browser window opens to pCloud's authorization page.
3. Sign in with your pCloud account and authorize CrispCloud.
4. The browser redirects back to CrispCloud.

### EU vs. US Server

pCloud operates two separate server clusters:
- **US servers**: `api.pcloud.com` (default)
- **EU servers**: `eapi.pcloud.com` (for accounts created on the EU cluster)

In the connection dialog, select **EU** or **US** based on where your pCloud account is hosted. If you are unsure, check your pCloud web interface — the URL will show `eapi` for EU accounts.

Using the wrong server results in authentication errors.

### Notes

- pCloud does not support versioning, sharing, thumbnails, or full-text search in the current CrispCloud adapter.

---

## Troubleshooting

### Connection Refused / Timeout

- Verify the hostname and port are correct.
- Check that the server is reachable (`ping` or `curl`) from your device.
- If using a proxy, verify it is configured correctly in **Settings → Network → Proxy**.
- For SFTP, check that the SSH daemon is running (`systemctl status sshd`).

### Authentication Failed

**Filen / Internxt**: double-check email and password. If 2FA is enabled, ensure the TOTP code is entered before it expires (codes rotate every 30 seconds).

**SFTP**: verify the username exists and the server permits the selected
authentication method. For a private key, check that the matching public key
is authorized by the server and that the passphrase is correct. Additional-
factor SSH logins are not supported by the current dialog.

**S3**: verify the access key is active and the IAM policy grants access to the specific bucket and region. Access keys are case-sensitive.

**Google Drive / OneDrive / Dropbox**: if the OAuth2 flow fails, try signing out of the provider in your browser first, then retrying the flow in CrispCloud.

**FTP**: allow the server's passive data-port range through its firewall. Select
the exact TLS mode and port required by the server; the app does not downgrade
a failed encrypted connection to plain FTP.

### TLS / Certificate Errors

- For servers with self-signed certificates, import the CA in **Settings → Network → Custom CAs**.
- If the server uses an outdated TLS version, set TLS mode to **Any** in **Settings → Network → TLS** (not recommended for production).
- Certificate pinning errors for Google/Microsoft/Dropbox/Amazon indicate a possible MITM attack or a corporate TLS inspection proxy. Configure the proxy's CA certificate in Custom CAs.

### Slow Transfer Speeds

- SFTP and S3 support true streaming; other providers buffer files. For large file transfers, prefer SFTP or S3.
- For S3, ensure the bucket region matches your geographic location to minimize latency.
- The transfer queue runs 3 concurrent transfers by default. This limit is configurable per-provider in **Settings → Transfers**.

### CORS Errors (Web PWA only)

If the browser console shows CORS errors for S3 or a custom WebDAV server, you must configure the server's CORS headers to allow the CrispCloud PWA origin. See the [S3 CORS section](#cors-configuration-web-pwa-only) above. For WebDAV servers, consult your server's documentation for CORS configuration.

### Quota Not Displayed

Some providers do not report storage quota. The status bar shows quota only when the provider returns it via the `getQuota()` API. Providers that support quota: Google Drive, OneDrive, Dropbox, Nextcloud, pCloud, SFTP (disk space), FTP (when server reports it).

### Multiple simultaneous cloud connections

Opening another connection keeps the existing authenticated client alive. Each
pane can select a different connection in its source dropdown; account labels
include the account identity. A local pane is preferred when the active pane
already shows a cloud. Paths and file operations remain bound to their exact
client, including its file-encryption wrapper. Connecting another server no
longer logs out the first one or deletes its saved credentials.

Additional live connections are session-only; this does not add a persistent
multi-account profile manager. Explicit disconnect still ends that session.
