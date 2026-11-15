# Reproduce the desktop qualification

Use Quds code commit `1cc4d251ebeb3e0cce205805e9183396da0c0df4` and CrispCloud
code commit `3c4cd0e24ab36f4fd88363cbc8521455bda811c6`, or check the canonical
file hashes in validation-receipt.json against a later checkout. Install the
official Dart 3.13.7 SDK. The recorded tests use genuine package:test and http.

Create an empty disposable validation directory and copy this evidence folder's
pubspec.yaml, pubspec.lock, run-focused.sh and extract-host-transport.py there.
Create `lib/src/zotero` and `test` beneath it. Copy the exact canonical
`packages/quds_office_engine/lib/src/zotero/zotero_client.dart` and
`zotero_models.dart` into `lib/src/zotero`, and copy canonical
`packages/quds_office_engine/test/zotero_client_test.dart` into `test`.

Run the supplied Python extraction script with explicit checkout/destination
paths, then its `--check` mode. It copies the actual production host transport
and unaltered transport test sections; it does not fabricate dependencies or
replace application code:

```sh
python extract-host-transport.py --crispcloud-root /path/to/CrispCloud --output /path/to/validation
python extract-host-transport.py --crispcloud-root /path/to/CrispCloud --output /path/to/validation --check
ZOTERO_VALIDATION_SDK=/path/to/dart-sdk bash run-focused.sh
```

The script reproduces the genuine compiler/VM/analyzer route. The exact original
commands, source hashes, dependency lock, installed SDK subset provenance and
original logs remain in validation-receipt.json and its referenced files.
A full SDK can also run `dart test` on both staged test files with the same Pub
resolution. Flutter UI/provider/native checks require a separate full Flutter
environment and are not represented by these 50 passing tests.
