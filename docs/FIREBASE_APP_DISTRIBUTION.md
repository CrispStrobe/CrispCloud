# Firebase App Distribution

CrispCloud Android betas use the permanent package ID
`com.crispstrobe.cloud` and the `Android Firebase Beta` GitHub Actions
workflow.

## Repository secrets

- `FIREBASE_APP_ID_ANDROID`: Firebase Android app ID for
  `com.crispstrobe.cloud`.
- `FIREBASE_SERVICE_ACCOUNT_JSON`: service-account JSON with Firebase App
  Distribution upload access.
- `ANDROID_KEYSTORE_BASE64`: base64-encoded stable upload keystore.
- `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`:
  credentials for that keystore.

The upload keystore must be backed up outside GitHub. Losing it prevents an
already-installed beta APK from being upgraded in place.

## Public tester link

After the first successful upload, create an invitation link under Firebase
Console > App Distribution > Invite links. Associate it with the external beta
tester group and publish that link on `crispstro.be` or LinkedIn.

Firebase invitation links are separate from Google Play closed testing and do
not satisfy Play's personal-account production-access requirement.
