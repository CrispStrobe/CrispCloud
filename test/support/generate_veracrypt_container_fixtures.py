#!/usr/bin/env python3
"""Independent, deterministic container fixtures (Python cryptography/OpenSSL).

Only public format facts are used. No application crypto code is imported.
Generated ciphertext is test data, never user data. Run from any directory.
SPDX-License-Identifier: MIT
"""

import base64
import hashlib
import struct
import zlib
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.argon2 import Argon2id

PASSWORD = b"container-fixture-password"
START = 131072
SIZE = 32 * 512
MASTER = bytes((i * 13 + 7) & 255 for i in range(256))
PAYLOAD = b"VeraCrypt bundled reader fixture.\n" * 37
NOTE = b"Nested encrypted file.\n"


def xts(data, key, unit):
    encryptor = Cipher(algorithms.AES(key), modes.XTS(unit.to_bytes(16, "little"))).encryptor()
    return encryptor.update(data) + encryptor.finalize()


def fat_entry(name, cluster, size=0, directory=False):
    entry = bytearray(32)
    if name in (".", ".."):
        entry[:11] = name.ljust(11).encode()
    else:
        base, _, ext = name.partition(".")
        entry[:11] = (base.ljust(8) + ext.ljust(3)).encode()
    entry[11] = 0x10 if directory else 0x20
    struct.pack_into("<H", entry, 24, ((2026 - 1980) << 9) | (11 << 5) | 15)
    struct.pack_into("<H", entry, 26, cluster)
    struct.pack_into("<I", entry, 28, size)
    return entry


def fat_image():
    image = bytearray(SIZE)
    image[:3] = bytes([0xEB, 0x3C, 0x90])
    image[3:11] = b"CRISPFAT"
    struct.pack_into("<H", image, 11, 512)
    image[13] = 1
    struct.pack_into("<H", image, 14, 1)
    image[16] = 2
    struct.pack_into("<H", image, 17, 16)
    struct.pack_into("<H", image, 19, 32)
    image[21] = 0xF8
    struct.pack_into("<H", image, 22, 1)
    image[38] = 0x29
    image[43:54] = b"CRISP TEST "
    image[54:62] = b"FAT12   "
    image[510:512] = b"\x55\xaa"
    fat = bytearray(512)
    for cluster, value in {0: 0xFF8, 1: 0xFFF, 2: 3, 3: 4, 4: 0xFFF, 5: 0xFFF, 6: 0xFFF}.items():
        offset = cluster * 3 // 2
        pair = int.from_bytes(fat[offset:offset + 2], "little")
        pair = (pair & 0x000F) | (value << 4) if cluster % 2 else (pair & 0xF000) | value
        fat[offset:offset + 2] = pair.to_bytes(2, "little")
    image[512:1024] = fat
    image[1024:1536] = fat
    image[1536:1568] = fat_entry("HELLO.TXT", 2, len(PAYLOAD))
    image[1568:1600] = fat_entry("DOCS", 5, directory=True)
    image[2048:2048 + len(PAYLOAD)] = PAYLOAD
    directory = 2048 + (5 - 2) * 512
    image[directory:directory + 32] = fat_entry(".", 5, directory=True)
    image[directory + 32:directory + 64] = fat_entry("..", 0, directory=True)
    image[directory + 64:directory + 96] = fat_entry("NOTE.TXT", 6, len(NOTE))
    image[4096:4096 + len(NOTE)] = NOTE
    return bytes(image)


def header(profile, hidden=False, backup=False):
    salt = bytes(((255 - i) if backup else i) for i in range(64))
    clear = bytearray(448)
    legacy = profile.startswith("truecrypt")
    clear[:4] = b"TRUE" if legacy else b"VERA"
    struct.pack_into(">H", clear, 4, 4 if profile == "truecrypt-v4" else 5)
    struct.pack_into(">H", clear, 6, 0x0600 if profile == "truecrypt-v4" else (0x0700 if legacy else 0x010B))
    struct.pack_into(">Q", clear, 28, SIZE if hidden else 0)
    struct.pack_into(">Q", clear, 36, SIZE)
    struct.pack_into(">Q", clear, 44, START)
    struct.pack_into(">Q", clear, 52, SIZE)
    struct.pack_into(">I", clear, 64, 0 if profile == "truecrypt-v4" else 512)
    clear[192:448] = MASTER
    struct.pack_into(">I", clear, 8, zlib.crc32(MASTER))
    struct.pack_into(">I", clear, 188, zlib.crc32(clear[:188]))
    if profile == "argon2id-pim1":
        key = Argon2id(salt=salt, length=192, iterations=3, lanes=1, memory_cost=65536).derive(PASSWORD)[:64]
    else:
        key = hashlib.pbkdf2_hmac("sha512", PASSWORD, salt, 1000 if legacy else 16000, 64)
    return salt + xts(bytes(clear), key, 0)


def dart_string(name, value):
    b64 = base64.b64encode(value).decode()
    lines = [f"const {name} ="]
    lines.extend("    '" + b64[i:i + 76] + "'" for i in range(0, len(b64), 76))
    lines[-1] += ";"
    return "\n".join(lines)


def main():
    plain = fat_image()
    encrypted = b"".join(xts(plain[i:i + 512], MASTER[:64], (START + i) // 512) for i in range(0, SIZE, 512))
    unknown = b"".join(xts(bytes(512), MASTER[:64], (START + i) // 512) for i in range(0, SIZE, 512))
    profiles = ["truecrypt-sha512", "truecrypt-v4", "vera-pim1", "argon2id-pim1"]
    declarations = [dart_string("_data", encrypted), dart_string("_unknownData", unknown)]
    cases = []
    for n, profile in enumerate(profiles):
        for hidden in (False, True):
            for backup in (False, True):
                name = f"_header{n}{int(hidden)}{int(backup)}"
                declarations.append(dart_string(name, header(profile, hidden, backup)))
                cases.append(f"    ('{profile}', {str(hidden).lower()}, {str(backup).lower()}) => {name},")
    result = """// Generated by generate_veracrypt_container_fixtures.py using Python/OpenSSL.
// SPDX-License-Identifier: MIT
// Header PBKDF/Argon2 and XTS data encryption do not call CrispCloud code.
import 'dart:convert';
import 'dart:typed_data';

const veraCryptFixturePassword = 'container-fixture-password';
final veraCryptFixtureContents = List.filled(37, 'VeraCrypt bundled reader fixture.\\n').join();
const veraCryptFixtureNote = 'Nested encrypted file.\\n';

Uint8List veraCryptContainerFixture({
  String profile = 'truecrypt-sha512',
  bool hidden = false,
  bool corruptPrimary = false,
  bool unsupportedFilesystem = false,
}) {
  final bytes = Uint8List(131072 + 16384 + 131072);
  String selected(bool backup) => switch ((profile, hidden, backup)) {
""" + "\n".join(cases) + """
    _ => throw ArgumentError.value(profile, 'profile'),
  };
  final primary = hidden ? 65536 : 0;
  final backup = bytes.length - (hidden ? 65536 : 131072);
  bytes.setRange(primary, primary + 512, base64Decode(selected(false)));
  bytes.setRange(backup, backup + 512, base64Decode(selected(true)));
  bytes.setRange(131072, 131072 + 16384, base64Decode(unsupportedFilesystem ? _unknownData : _data));
  if (corruptPrimary) bytes[primary + 144] ^= 1;
  return bytes;
}

""" + "\n\n".join(declarations) + "\n"
    destination = Path(__file__).with_name("veracrypt_container_fixture.dart")
    destination.write_text(result)
    print(f"Wrote {destination.name}: {len(result)} bytes; data SHA256 {hashlib.sha256(encrypted).hexdigest()}")


if __name__ == "__main__":
    main()
