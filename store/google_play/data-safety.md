# Data safety answers

These answers describe the current release. Re-evaluate them whenever an
analytics, crash-reporting, advertising, authentication, or backend SDK is
added.

## Recommended declaration

- Does the app collect or share required user-data categories? **No**
- Is all user data encrypted in transit? **Yes, when the configured provider
  uses TLS/SSH.** CrispCloud also permits user-configured plain FTP and HTTP
  WebDAV endpoints, so do not make an unconditional Play claim unless those
  insecure schemes are disabled for the Play build.
- Can users request deletion? **Not applicable to the developer: CrispCloud has
  no developer-operated account or backend.** Users delete local app data by
  disconnecting accounts/clearing app storage and manage remote data with the
  selected storage provider.
- Privacy policy URL:
  `https://crisp-cloud.vercel.app/privacy.html`

## Reasoning

CrispCloud sends files and credentials directly to storage providers selected
by the user. The developer does not receive that data. Credentials, settings,
analytics events, audit logs and crash reports are stored locally. There is no
advertising SDK, external analytics SDK, Firebase SDK, or remote crash backend
in this release.

Google's definition—not ordinary dictionary meaning—controls the console form.
If Play Console treats transfers to a user-selected third-party provider as
collection for a particular question, disclose the corresponding categories
instead of relying on this draft.
