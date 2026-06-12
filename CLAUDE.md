# CrispCloud

## Toolchain

- **Flutter**: `/mnt/volume1/toolchain/flutter/bin/flutter` (v3.44.1, stable channel, Dart 3.12.1)
- **Pub cache**: `/mnt/volume1/pub-cache`

## Build commands

```bash
FLUTTER=/mnt/volume1/toolchain/flutter/bin/flutter

$FLUTTER pub get
$FLUTTER analyze
$FLUTTER test

# Web build (always inject version + git hash for about dialog)
GIT_HASH=$(git rev-parse --short HEAD)
APP_VERSION=$(grep '^version:' pubspec.yaml | cut -d' ' -f2)
$FLUTTER build web --release \
  --dart-define=GIT_HASH=$GIT_HASH \
  --dart-define=APP_VERSION=$APP_VERSION
```

## Deploy to Vercel

```bash
cp vercel.json build/web/vercel.json
mkdir -p build/web/.vercel
echo '{"projectId":"prj_hqMY3wQr238SVaiWzRKCh9pyDzfs","orgId":"team_uvAE8yHK3Zi7pXobhJmwckcQ"}' > build/web/.vercel/project.json
source ~/.env
cd build/web && vercel deploy --prod --yes --token="$VERCEL_TOKEN"
```
