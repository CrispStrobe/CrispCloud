# SPDX-License-Identifier: MPL-2.0
"""Independent, deliberately scoped CFB/CLX/HFD reader for the two retained DOCs.

This is a read-only evidence oracle, not a general DOC parser. It supports the
version-3, header-only DIFAT and uncompressed CLX pieces used by these fixtures.
Primary layouts: MS-CFB Header/Directory/MiniFAT; MS-DOC Clx/PlcPcd/Pcd;
MS-DOC NilPICFAndBinData/HFD; MS-OSHARED Hyperlink Object/URLMoniker.
"""
import hashlib
import struct


def require(value, message):
    if not value:
        raise ValueError(message)


def u16(data, offset):
    require(0 <= offset <= len(data) - 2, 'Bounded u16')
    return struct.unpack_from('<H', data, offset)[0]


def u32(data, offset):
    require(0 <= offset <= len(data) - 4, 'Bounded u32')
    return struct.unpack_from('<I', data, offset)[0]


def streams(data):
    require(data[:8] == bytes.fromhex('d0cf11e0a1b11ae1'), 'CFB signature')
    require(len(data) <= 1024 * 1024 and len(data) % 512 == 0, 'Small complete fixture sectors')
    require(u16(data, 26) == 3 and u16(data, 30) == 9 and u16(data, 32) == 6, 'Version-3 sector sizes')
    require(u32(data, 72) == 0 and u32(data, 44) <= 109, 'Fixture header DIFAT only')
    def sector(index):
        require(index < len(data) // 512 - 1, 'Bounded sector')
        return data[(index + 1) * 512:(index + 2) * 512]
    fat = []
    for i in range(u32(data, 44)):
        fat.extend(struct.unpack('<128I', sector(u32(data, 76 + 4 * i))))
    def chain(start, table, read):
        seen, result = set(), []
        while start != 0xfffffffe:
            require(start < len(table) and start not in seen, 'Acyclic bounded chain')
            seen.add(start)
            result.append(read(start))
            start = table[start]
        return b''.join(result)
    directory = chain(u32(data, 48), fat, sector)
    entries = []
    for offset in range(0, len(directory), 128):
        entry = directory[offset:offset + 128]
        if entry[66] == 0:
            continue
        length = u16(entry, 64)
        require(2 <= length <= 64 and length % 2 == 0, 'Directory name extent')
        entries.append((entry[:length - 2].decode('utf-16le'), entry[66], u32(entry, 116), u32(entry, 120)))
    roots = [e for e in entries if e[1] == 5]
    require(len(roots) == 1, 'Unique mini-stream root')
    mini_stream = chain(roots[0][2], fat, sector)[:roots[0][3]]
    mini_fat_raw = chain(u32(data, 60), fat, sector)
    require(len(mini_fat_raw) == u32(data, 64) * 512, 'Mini-FAT extent')
    mini_fat = struct.unpack('<' + 'I' * (len(mini_fat_raw) // 4), mini_fat_raw)
    def mini(index):
        require((index + 1) * 64 <= len(mini_stream), 'Bounded mini sector')
        return mini_stream[index * 64:(index + 1) * 64]
    result = {}
    for name, kind, start, size in entries:
        if kind != 2 or not size:
            continue
        require(name not in result, 'Unique fixture stream name')
        value = chain(start, mini_fat, mini) if size < u32(data, 56) else chain(start, fat, sector)
        require(len(value) >= size, 'Complete stream')
        result[name] = value[:size]
    return result


def cp_text(source):
    word = source['WordDocument']
    table = source['1Table' if u16(word, 10) & 0x200 else '0Table']
    at = 32
    at += 2 + 2 * u16(word, at)
    at += 2 + 4 * u16(word, at)
    require(u16(word, at) > 33, 'FIB includes CLX')
    offset, size = struct.unpack_from('<II', word, at + 2 + 33 * 8)
    require(offset + size <= len(table), 'CLX extent')
    clx = table[offset:offset + size]
    at = 0
    while at < len(clx) and clx[at] == 1:
        at += 3 + u16(clx, at + 1)
    require(at + 5 <= len(clx) and clx[at] == 2, 'Pcdt marker')
    size = u32(clx, at + 1)
    plc = clx[at + 5:at + 5 + size]
    require(len(plc) == size and size >= 16 and (size - 4) % 12 == 0, 'PlcPcd extent')
    count = (size - 4) // 12
    cps = [u32(plc, 4 * i) for i in range(count + 1)]
    require(cps[0] == 0 and all(a < b for a, b in zip(cps, cps[1:])), 'Ordered CP pieces')
    result = bytearray()
    positions = []
    for i in range(count):
        fc = u32(plc, 4 * (count + 1) + 8 * i + 2)
        require(fc < 0x40000000, 'Fixture uses uncompressed UTF-16 pieces')
        length = 2 * (cps[i + 1] - cps[i])
        require(fc + length <= len(word), 'Piece FC extent')
        result.extend(word[fc:fc + length])
        positions.extend(range(fc, fc + length, 2))
    return bytes(result), positions


def marker_properties(source, fc):
    word = source['WordDocument']
    table = source['1Table' if u16(word, 10) & 0x200 else '0Table']
    at = 32
    at += 2 + 2 * u16(word, at)
    at += 2 + 4 * u16(word, at)
    offset, length = struct.unpack_from('<II', word, at + 2 + 12 * 8)
    require(length >= 12 and (length - 4) % 8 == 0 and offset + length <= len(table), 'CHPX bin extent')
    bins = (length - 4) // 8
    pages, matches = set(), []
    for i in range(bins):
        page = (u32(table, offset + (bins + 1) * 4 + i * 4) & 0x3fffff) * 512
        if page in pages:
            continue
        pages.add(page)
        require(page + 512 <= len(word), 'CHPX page extent')
        count = word[page + 511]
        for j in range(count):
            if u32(word, page + 4 * j) <= fc < u32(word, page + 4 * (j + 1)):
                at = page + 2 * word[page + (count + 1) * 4 + j]
                require(at > page and at + 1 + word[at] <= page + 511, 'CHPX operand extent')
                matches.append(word[at + 1:at + 1 + word[at]])
    require(len(matches) == 1, 'Unique actual marker CHPX')
    data, at, properties = matches[0], 0, {}
    while at < len(data):
        op = u16(data, at)
        size = [1, 1, 2, 4, 2, 2, None, 3][op >> 13]
        require(size is not None and at + 2 + size <= len(data), 'Fixture fixed CHPX property extent')
        properties.setdefault(op, []).append(data[at + 2:at + 2 + size])
        at += 2 + size
    require(properties.get(0x0855) == [b'\1'] and properties.get(0x0806) == [b'\1'], 'Actual CFSpec and CFData')
    require(len(properties.get(0x6a03, [])) == 1, 'Unique CPicLocation')
    return u32(properties[0x6a03][0], 0), data.hex()


def hfd(raw):
    require(len(raw) >= 99 and u32(raw, 0) == len(raw) and u16(raw, 4) == 68, 'NilPICF header')
    require(raw[69:85] == bytes.fromhex('d0c9ea79f9bace118c8200aa004ba90b') and u32(raw, 85) == 2, 'HFD class/version')
    flags = u32(raw, 89)
    if raw[68] == 0 and flags == 3:
        require(raw[93:109] == bytes.fromhex('e0c9ea79f9bace118c8200aa004ba90b'), 'URL moniker class')
        end = 113 + u32(raw, 109)
        require(end == len(raw), 'Exact URL moniker extent')
        value = raw[113:end]
        kind, extra = 'URLMoniker', 0
    else:
        require(raw[68] == 8 and flags in (8, 10), 'Location-only HFD')
        end = 97 + 2 * u32(raw, 93)
        require(end <= len(raw), 'Bounded location')
        value = raw[97:end]
        extra = len(raw) - end
        require(extra in (0, 2) and raw[end:] == b'\0' * extra, 'Recorded zero word only')
        kind = 'location'
    require(len(value) >= 4 and len(value) % 2 == 0 and value[-2:] == b'\0\0', 'Terminated UTF-16')
    text = value[:-2].decode('utf-16le')
    require(all(ord(c) >= 0x20 and ord(c) not in (0xfffe, 0xffff) for c in text), 'Printable target')
    return {'kind': kind, 'target': text, 'flags': flags, 'extraZeroBytes': extra,
            'sha256': hashlib.sha256(raw).hexdigest()}


def verify_source(data, inspection, *, reference=False):
    source = streams(data)
    text, positions = cp_text(source)
    require(hashlib.sha256(data).hexdigest() == inspection.get('sourceSha256'), 'Inspection source bytes')
    artifacts = inspection['artifacts' if reference else 'binaryData']
    fields = inspection['fields']
    require(len(fields) == (3 if reference else 4) and
            len({f['startCp'] for f in fields}) == len(fields), 'Exact native field inspection inventory')
    require(len(artifacts) == (2 if reference else 4) and
            len({a['cp'] for a in artifacts}) == len(artifacts), 'Exact binary artifact inspection inventory')
    seen = []
    for field in fields:
        start, end, separator = field['startCp'], field['endCp'], field['separatorCp']
        require(text[2 * start:2 * start + 2] == b'\x13\0', 'Actual field begin CP')
        require(text[2 * separator:2 * separator + 2] == b'\x14\0', 'Actual field separator CP')
        require(text[2 * (end - 1):2 * end] == b'\x15\0', 'Actual field end CP')
        literal = text[2 * (start + 1):2 * separator].decode('utf-16le')
        require(literal == field['instruction'], 'Independent CLX literal instruction')
        require(text[2 * (separator + 1):2 * (end - 1)].decode('utf-16le') == field['storedResult'],
                'Independent CLX cached result')
        if '\x01' not in literal:
            continue
        cp = start + 1 + literal.index('\x01')
        matches = [a for a in artifacts if a['cp'] == cp]
        require(len(matches) == 1, 'Unique inspected binary data CP')
        a = matches[0]
        pointer, properties = marker_properties(source, positions[cp])
        require(pointer == a['offset'], 'Independent CPicLocation points to Data range')
        raw = source['Data'][a['offset']:a['offset'] + a['length']]
        result = hfd(raw)
        require(result['sha256'] == a['sha256'], 'Independent Data stream range')
        require(result['target'] in literal, 'Target is literal source text')
        seen.append({'cp': cp, 'fc': positions[cp], 'dataOffset': pointer,
                     'markerChpxHex': properties, 'instruction': literal, **result})
    require(len(seen) == (2 if reference else 4), 'All native HFD fields')
    return seen
