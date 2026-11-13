"""Check independently sourced ADC/XZ streams in UDIF with installed 7-Zip."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zlib


def udif(raw, packed, method):
    table = bytearray(284)
    struct.pack_into('>4sIQQQII', table, 0, b'mish', 1, 0, len(raw) // 512, 0,
                     len(raw) // 512, 0)
    struct.pack_into('>III', table, 64, 2, 32, zlib.crc32(raw))
    struct.pack_into('>I', table, 200, 2)
    struct.pack_into('>IIQQQQ', table, 204, method, 0, 0, len(raw) // 512, 0,
                     len(packed))
    struct.pack_into('>IIQQQQ', table, 244, 0xffffffff, 0, len(raw) // 512, 0, 0, 0)
    xml = plistlib.dumps({'resource-fork': {'blkx': [
        {'Name': 'Codec fixture', 'Data': bytes(table)}
    ]}})
    footer = bytearray(512)
    struct.pack_into('>4sIII', footer, 0, b'koly', 4, 512, 1)
    struct.pack_into('>Q', footer, 32, len(packed))
    struct.pack_into('>II', footer, 56, 1, 1)
    struct.pack_into('>QQ', footer, 216, len(packed), len(xml))
    struct.pack_into('>IQ', footer, 488, 1, len(raw) // 512)
    return packed + xml + footer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sevenzip', required=True)
    args = parser.parse_args()
    fixtures = Path(__file__).resolve().parents[1] / 'fixtures/archives/dmg-codecs'
    results = []
    with tempfile.TemporaryDirectory(prefix='crisp-dmg-codecs-') as temp:
        for name, plain, method in [
            ('apple-hdiutil.adc', 'apple-hdiutil.bin', 0x80000004),
            ('liblzma-1m.xz', 'liblzma.bin', 0x80000008),
        ]:
            raw = (fixtures / plain).read_bytes()
            packed = (fixtures / name).read_bytes()
            image = Path(temp) / (name + '.dmg')
            image.write_bytes(udif(raw, packed, method))
            checked = subprocess.run([args.sevenzip, 'x', '-so', '-tdmg', str(image)],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     timeout=30, check=True)
            if checked.stdout != raw:
                raise ValueError(f'{name}: independently extracted bytes differ')
            results.append({'fixture': name, 'bytes': len(raw),
                            'sha256': hashlib.sha256(checked.stdout).hexdigest()})
    print(json.dumps({'independent_dmg_extraction': results}, indent=2))


if __name__ == '__main__':
    main()
