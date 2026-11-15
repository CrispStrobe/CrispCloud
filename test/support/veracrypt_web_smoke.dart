// SPDX-License-Identifier: MIT
// Compile with dart compile js, then execute with node. Uses independent
// encrypted FAT fixtures; no browser or native filesystem is required.
import 'dart:convert';

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/veracrypt_container_reader.dart';
import 'package:crisp_cloud/services/veracrypt_service.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'veracrypt_container_fixture.dart';

Future<void> main() async {
  for (final profile in [
    (
      'truecrypt-sha512',
      const VeraCryptUnlockOptions(
        trueCryptMode: true,
        kdf: VeraCryptKdf.sha512,
      ),
    ),
    (
      'vera-pim1',
      const VeraCryptUnlockOptions(kdf: VeraCryptKdf.sha512, pim: 1),
    ),
  ]) {
    final archive = await openVeraCryptArchive(
      koni.MemoryByteSource(veraCryptContainerFixture(profile: profile.$1)),
      password: veraCryptFixturePassword,
      options: profile.$2,
    );
    final file = archive.members.singleWhere(
      (member) => member.name == 'HELLO.TXT',
    );
    if (utf8.decode(await archive.readMember(file)) !=
        veraCryptFixtureContents) {
      throw StateError('Incorrect decrypted ${profile.$1} FAT contents.');
    }
    final note = archive.members.singleWhere(
      (member) => member.name == 'DOCS/NOTE.TXT',
    );
    if (utf8.decode(await archive.readMember(note)) != veraCryptFixtureNote) {
      throw StateError('Incorrect nested FAT contents.');
    }
    await archive.close();
    try {
      await archive.readMember(file);
      throw StateError('Closed volume accepted a file read.');
    } on ArchiveViewException {
      // Expected closed-session error.
    }
  }
  // ignore: avoid_print -- executable validation receipt, not application logs.
  print(
    'PASS: compiled-JavaScript VeraCrypt PIM and native-header TrueCrypt '
    'FAT listing, cross-sector file reads, nested files and closed sessions.',
  );
}
