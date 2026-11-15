#!/usr/bin/env python3
"""Independent deterministic interoperability vectors; no CrispCloud crypto.

Requires Python cryptography with Argon2id (tested with 50.0.0), hashlib, and
OpenSSL 3 with its legacy provider for Whirlpool. Never run on user secrets.
Fixtures are small encrypted headers/data, not complete mountable filesystems.

Format references:
https://veracrypt.io/en/Header%20Key%20Derivation.html
https://veracrypt.io/en/Personal%20Iterations%20Multiplier%20(PIM).html
https://veracrypt.io/en/VeraCrypt%20Volume%20Format%20Specification.html
Keyfile mixing cross-checked against the Apache-2.0 independent implementation:
https://github.com/norsehorse-dev/VaultPonyCore/blob/f746a3af6448636eba837ea62de2e432d3f0e6a5/core/vc-crypto/src/keyfile.rs

Generated fixture bytes are test data, independent of production Dart code.
"""
from __future__ import annotations

import base64
import hashlib
import json
import struct
import subprocess
import zlib
from pathlib import Path

import cryptography
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.argon2 import Argon2id

SALT = bytes(range(64))
MASTER = bytes((index * 29 + 17) % 256 for index in range(256))
DATA = bytes((index * 7 + index // 13 + 3) % 256 for index in range(1024))
PASSWORD = "crisp-vector-password-long"
KEYFILES = [bytes(range(256)) + b"keyfile-one", b"second\x00binary\xffkeyfile"]


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def mix(password: str, keyfiles: list[bytes]) -> bytes:
    """Use zlib's incremental CRC instead of reproducing the Dart CRC table."""
    raw = password.encode("utf-8")
    if not keyfiles:
        return raw
    length = 64 if len(raw) <= 64 else 128
    pool = bytearray(length)
    for keyfile in keyfiles:
        crc = 0
        cursor = 0
        for byte in keyfile[:1024 * 1024]:
            crc = zlib.crc32(bytes([byte]), crc)
            state = (crc ^ 0xffffffff).to_bytes(4, "big")
            for state_byte in state:
                pool[cursor] = (pool[cursor] + state_byte) % 256
                cursor = (cursor + 1) % length
    padded = raw.ljust(length, b"\0")
    return bytes((left + right) % 256 for left, right in zip(padded, pool))


def derive(kdf: str, secret: bytes, pim: int, truecrypt: bool) -> bytes:
    if kdf == "argon2id":
        effective = pim or 12
        memory_mib = min(64 + (effective - 1) * 32, 1024)
        passes = 3 + (effective - 1) // 3 if effective <= 31 else 13 + effective - 31
        return Argon2id(salt=SALT, length=192, iterations=passes, lanes=1,
                       memory_cost=memory_mib * 1024).derive(secret)[:64]
    count = ((2000 if kdf == "ripemd160" else 1000) if truecrypt else
             15000 + pim * 1000 if pim else
             655331 if kdf == "ripemd160" else 500000)
    if kdf != "whirlpool":
        return hashlib.pbkdf2_hmac(kdf, secret, SALT, count, dklen=64)
    # hashlib's provider does not expose Whirlpool in this test environment.
    # Invoke the independent OpenSSL KDF with deterministic public test input.
    return subprocess.run([
        "openssl", "kdf", "-provider", "default", "-provider", "legacy",
        "-binary", "-keylen", "64", "-kdfopt", "digest:whirlpool",
        "-kdfopt", f"hexpass:{secret.hex()}", "-kdfopt", f"hexsalt:{SALT.hex()}",
        "-kdfopt", f"iter:{count}", "PBKDF2",
    ], check=True, capture_output=True).stdout


def xts(data: bytes, key: bytes, unit: int) -> bytes:
    operation = Cipher(algorithms.AES(key), modes.XTS(unit.to_bytes(16, "little"))).encryptor()
    return operation.update(data) + operation.finalize()


def clear_header(*, truecrypt: bool = False, version: int = 5,
                 data_offset: int = 131072, sector: int = 512,
                 hidden: bool = False) -> bytearray:
    header = bytearray(448)
    header[:4] = b"TRUE" if truecrypt else b"VERA"
    struct.pack_into(">HH", header, 4, version,
                     0x0600 if truecrypt and version == 4 else
                     0x071a if truecrypt else 0x010b)
    struct.pack_into(">Q", header, 28, 4096 if hidden else 0)
    struct.pack_into(">QQQ", header, 36, 4096, data_offset, 4096)
    struct.pack_into(">I", header, 64, sector if version >= 5 else 0)
    header[192:448] = MASTER
    fix_crcs(header)
    return header


def fix_crcs(header: bytearray) -> None:
    struct.pack_into(">I", header, 8, zlib.crc32(header[192:448]))
    struct.pack_into(">I", header, 188, zlib.crc32(header[:188]))


def fixture(name: str, kdf: str, pim: int = 0, *, truecrypt: bool = False,
            version: int = 5, password: str = PASSWORD,
            keyfiles: list[bytes] | None = None, hidden: bool = False,
            sector: int = 512, required_version: int | None = None) -> dict:
    keyfiles = keyfiles or []
    secret = mix(password, keyfiles)
    key = derive(kdf, secret, pim, truecrypt)
    offset = 196608 if hidden else 131072
    clear = clear_header(truecrypt=truecrypt, version=version,
                         data_offset=offset, sector=sector, hidden=hidden)
    if required_version is not None:
        struct.pack_into(">H", clear, 6, required_version)
        fix_crcs(clear)
    encrypted_data = b"".join(xts(DATA[i:i+512], MASTER[:64], (offset+i)//512)
                              for i in range(0, len(DATA), 512))
    return {
        "name": name, "kdf": kdf, "pim": pim, "trueCryptMode": truecrypt,
        "password": password, "keyfiles": [b64(k) for k in keyfiles],
        "mixedPasswordHex": secret.hex(), "headerKeyHex": key.hex(),
        "header": b64(SALT + xts(clear, key, 0)), "version": version,
        "sectorSize": sector, "hiddenVolumeSize": 4096 if hidden else 0,
        "dataOffset": offset, "dataSize": 4096,
        "containerSize": offset + 4096 + 131072,
        "dataCiphertext": b64(encrypted_data), "dataPlaintext": b64(DATA),
    }


def main() -> None:
    vectors = [
        fixture("veracrypt_sha512_pim1", "sha512", 1),
        fixture("veracrypt_sha256_pim2", "sha256", 2),
        fixture("veracrypt_whirlpool_pim1", "whirlpool", 1),
        fixture("veracrypt_ripemd160_pim1", "ripemd160", 1),
        fixture("veracrypt_sha512_keyfiles", "sha512", 1, keyfiles=KEYFILES),
        fixture("veracrypt_sha512_long_keyfiles", "sha512", 1,
                keyfiles=KEYFILES, password="\u00e4" * 40),
        fixture("veracrypt_sha512_keyfiles_only", "sha512", 1,
                keyfiles=KEYFILES, password=""),
        fixture("truecrypt_v4_sha512", "sha512", truecrypt=True, version=4),
        fixture("truecrypt_v5_sha512", "sha512", truecrypt=True),
        fixture("truecrypt_v5_ripemd160", "ripemd160", truecrypt=True),
        fixture("truecrypt_v5_whirlpool", "whirlpool", truecrypt=True),
        fixture("truecrypt_v5_keyfiles", "sha512", truecrypt=True, keyfiles=KEYFILES),
        fixture("veracrypt_hidden_4096", "sha512", 1, hidden=True, sector=4096),
        fixture("veracrypt_current_required", "sha512", 1, required_version=0x0126),
        fixture("veracrypt_argon2id_pim1", "argon2id", 1),
    ]
    base = next(v for v in vectors if v["name"] == "truecrypt_v5_sha512")
    key = bytes.fromhex(base["headerKeyHex"])
    invalid = []
    for name, offset, fmt, value in [
        ("future_header", 4, ">H", 6),
        ("pre_xts_header", 4, ">H", 3),
        ("future_truecrypt", 6, ">H", 0x0800),
        ("old_truecrypt", 6, ">H", 0x0500),
        ("system_volume", 60, ">I", 1),
        ("in_place_volume", 60, ">I", 2),
        ("unknown_flags", 60, ">I", 4),
        ("invalid_sector", 64, ">I", 1536),
        ("zero_volume", 36, ">Q", 0),
        ("partial_data", 52, ">Q", 512),
        ("before_data", 44, ">Q", 512),
        ("unaligned_data", 44, ">Q", 131073),
        ("outside_container", 44, ">Q", 262144),
        ("unsafe_js_integer", 44, ">Q", (1 << 53) + 1),
        ("overflow_geometry", 44, ">Q", (1 << 53) - 512),
        ("wrong_hidden_size", 28, ">Q", 512),
    ]:
        clear = clear_header(truecrypt=True)
        struct.pack_into(fmt, clear, offset, value)
        fix_crcs(clear)
        invalid.append({"name": name, "header": b64(SALT + xts(clear, key, 0))})
    for name, offset in [("damaged_fields_crc", 100), ("damaged_key_crc", 400)]:
        clear = clear_header(truecrypt=True)
        clear[offset] ^= 1
        invalid.append({"name": name, "header": b64(SALT + xts(clear, key, 0))})
    vc_key = bytes.fromhex(vectors[0]["headerKeyHex"])
    future_vc = clear_header()
    struct.pack_into(">H", future_vc, 6, 0x0127)
    fix_crcs(future_vc)
    corpus = {
        "generator": "Python hashlib/zlib, cryptography AES-XTS/Argon2id and OpenSSL Whirlpool",
        "cryptographyVersion": cryptography.__version__,
        "saltHex": SALT.hex(), "vectors": vectors, "invalidHeaders": invalid,
        "futureVeraCryptHeader": b64(SALT + xts(future_vc, vc_key, 0)),
        "keyfileTruncation": {
            "password": PASSWORD,
            "pattern": "bytes(range(256)) repeated 4096 times (one MiB), then arbitrary suffix",
            "mixedPasswordHex": mix(PASSWORD, [bytes(range(256)) * 4096]).hex(),
        },
    }
    output = Path(__file__).with_name("compatibility_vectors.json")
    output.write_text(json.dumps(corpus, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(vectors)} valid and {len(invalid)} invalid independent vectors to {output}")


if __name__ == "__main__":
    main()
