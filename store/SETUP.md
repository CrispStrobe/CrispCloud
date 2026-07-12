# App Store / Play Store — Setup Checklist

## App Store Connect (iOS)

App ID: `6789570314`
Bundle ID: `com.CrispStrobe.cloud` (resource ID: `9V83V56K2C`)
Team ID: `N9XSJ4M3GT`
API Key ID: `9RMU3C7422`
Version: `1.0` (PREPARE_FOR_SUBMISSION)

### GitHub repo secrets needed for CI signing

| Secret | Description |
|--------|-------------|
| `APPSTORE_API_KEY_P8` | base64 of `AuthKey_9RMU3C7422.p8` |

Set with:
```bash
base64 -w0 /mnt/volume1/AuthKey_9RMU3C7422.p8 | gh secret set APPSTORE_API_KEY_P8 -R CrispStrobe/CrispCloud
```

### Remaining browser-only steps

1. **Non-Trader status** — App Store Connect → Business → Non-Trader
2. **App Privacy** — App Store Connect → App Privacy → Data Not Collected
3. **Version number** — pubspec.yaml version must match ASC version at upload
   - Either bump pubspec to `1.0.0+1` or change ASC to `0.2.2`

### Local Mac build (alternative to CI)

```bash
# 1. One-time: migrate plugins
flutter build ios --release --no-codesign

# 2. Archive
PATH="/usr/bin:$PATH" xcodebuild \
  -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -archivePath build/ios/archive/Runner.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath /mnt/volume1/AuthKey_9RMU3C7422.p8 \
  -authenticationKeyID 9RMU3C7422 \
  -authenticationKeyIssuerID 5f618ba3-98ef-42ad-835c-fbbef6c76cf5 \
  archive

# 3. Export
PATH="/usr/bin:$PATH" xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/export \
  -exportOptionsPlist .appstoreconnect/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath /mnt/volume1/AuthKey_9RMU3C7422.p8 \
  -authenticationKeyID 9RMU3C7422 \
  -authenticationKeyIssuerID 5f618ba3-98ef-42ad-835c-fbbef6c76cf5

# 4. Upload
xcrun altool --upload-package build/ios/export/Runner.ipa \
  --type ios --apple-id 6789570314 --bundle-id com.CrispStrobe.cloud \
  --bundle-version 1 --bundle-short-version-string 1.0.0 \
  --api-key 9RMU3C7422 --api-issuer 5f618ba3-98ef-42ad-835c-fbbef6c76cf5
```

## Google Play (Android)

Package: `com.CrispStrobe.cloud_dart`

### Keystore setup

```bash
keytool -genkey -v -keystore android/crisp-cloud-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias crispcloud

# Then fill in android/key.properties from key.properties.example
```

### GitHub repo secrets for CI

| Secret | Description |
|--------|-------------|
| `ANDROID_KEYSTORE_BASE64` | base64 of the .jks file |
| `ANDROID_KEY_ALIAS` | `crispcloud` |
| `ANDROID_KEY_PASSWORD` | password you set |
| `ANDROID_STORE_PASSWORD` | keystore password |

### Build AAB for Play Store

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```
