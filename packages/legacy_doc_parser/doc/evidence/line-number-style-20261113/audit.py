#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Independent bounded CFB/STSH audit of the retained Line Number control."""
import hashlib
import struct


SOURCE_SHA256 = 'c904414c506dffed61181846198dd1e097f19e2e1cf85b7e27c46513d3cae7fe'
STD_HEX = ('2810f20001013e0000000b006c0069006e00650020006e0075006d006200650072000000'
           '1800422a067068cc2233004f4a0800514a0800434a1c00350801')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def u16(data, at):
    return struct.unpack_from('<H', data, at)[0]


def u32(data, at):
    return struct.unpack_from('<I', data, at)[0]


def stream(data, name):
    """Read only the bounded v3 CFB layout used by the checked native sources."""
    require(data[:8] == bytes.fromhex('d0cf11e0a1b11ae1'), 'CFB signature')
    require(u16(data, 26) == 3 and u16(data, 30) == 9, 'CFB sector layout')
    require(u16(data, 32) == 6 and u32(data, 56) == 4096, 'CFB mini-stream layout')
    require(u32(data, 72) == 0, 'Extended DIFAT unsupported by this audit')

    def sector(index):
        at = (index + 1) * 512
        require(0 <= at <= len(data) - 512, 'Sector exceeds source')
        return data[at:at + 512]

    fat = []
    for index in struct.unpack_from('<109I', data, 76):
        if index < 0xfffffffa:
            fat.extend(struct.unpack('<128I', sector(index)))

    def chain(start, allocation, reader):
        result, seen = bytearray(), set()
        while start < 0xfffffffa:
            require(start not in seen and start < len(allocation), 'Invalid CFB chain')
            seen.add(start)
            result.extend(reader(start))
            start = allocation[start]
        return bytes(result)

    directory = chain(u32(data, 48), fat, sector)
    entries = {}
    for at in range(0, len(directory), 128):
        entry = directory[at:at + 128]
        length = u16(entry, 64)
        if not length:
            continue
        require(2 <= length <= 64 and length % 2 == 0, 'CFB directory name')
        key = entry[:length - 2].decode('utf-16le')
        require(key not in entries, 'Duplicate CFB name')
        entries[key] = (u32(entry, 116), struct.unpack_from('<Q', entry, 120)[0])
    start, size = entries[name]
    if size >= 4096:
        result = chain(start, fat, sector)
    else:
        root_start, root_size = entries['Root Entry']
        mini = chain(root_start, fat, sector)[:root_size]
        raw_fat = chain(u32(data, 60), fat, sector)
        mini_fat = struct.unpack('<%dI' % (len(raw_fat) // 4), raw_fat)

        def mini_sector(index):
            require(index * 64 <= len(mini) - 64, 'Mini-sector exceeds source')
            return mini[index * 64:index * 64 + 64]

        result = chain(start, mini_fat, mini_sector)
    require(size <= len(result), 'Truncated CFB stream')
    return result[:size]


def raw_styles(data):
    word = stream(data, 'WordDocument')
    require(u16(word, 32) == 14 and u16(word, 62) == 22, 'Unexpected FIB sizes')
    table_name = '1Table' if u16(word, 10) & 0x200 else '0Table'
    table = stream(data, table_name)
    require(u16(word, 152) >= 32, 'FIB pair count')
    pair = lambda index: (u32(word, 154 + index * 8), u32(word, 158 + index * 8))
    offset, length = pair(1)
    raw = table[offset:offset + length]
    require(len(raw) == length, 'Truncated STSH')
    header, count, base = u16(raw, 0), u16(raw, 2), u16(raw, 4)
    require(base == 10 and count <= 4096 and header >= 4, 'Unexpected STSH layout')
    styles, cursor = [], 2 + header
    for index in range(count):
        size = u16(raw, cursor)
        cursor += 2
        if not size:
            continue
        record = raw[cursor:cursor + size]
        cursor += size
        require(len(record) == size, 'Truncated STD')
        name_length = u16(record, base)
        name_end = base + 2 + 2 * name_length
        require(u16(record, name_end) == 0, 'Unterminated STD name')
        styles.append({'index': index, 'builtinId': u16(record, 0) & 0xfff,
                       'kind': u16(record, 2) & 15, 'parentIndex': u16(record, 2) >> 4,
                       'name': record[base + 2:name_end].decode('utf-16le'),
                       'rawHex': record.hex()})
    dop, dop_length = pair(31)
    require(dop_length >= 10, 'DOP too short for Copts60')
    return {'nFib': u16(word, 2), 'tableStream': table_name, 'styles': styles,
            'copts60': table[dop + 8:dop + 10].hex()}


def audit_control(data):
    require(hashlib.sha256(data).hexdigest() == SOURCE_SHA256, 'Line style source hash')
    raw = raw_styles(data)
    styles = [style for style in raw['styles'] if style['builtinId'] == 40]
    require(len(styles) == 1, 'Expected exactly one source Line Number style')
    style = styles[0]
    require(style == {'index': 16, 'builtinId': 40, 'kind': 2, 'parentIndex': 15,
                      'name': 'line number', 'rawHex': STD_HEX}, 'Explicit STD changed')
    # Each operand is checked against authored constants, not parser or native
    # DOCX interpretation. This fixture has one current CHPX set, no revision.
    record = bytes.fromhex(style['rawHex'])
    start = 10 + 4 + 2 * len(style['name'])
    count = u16(record, start)
    props = record[start + 2:start + 2 + count]
    require(props == bytes.fromhex('422a067068cc2233004f4a0800514a0800434a1c00350801'),
            'Line style CHPX changed')
    word = stream(data, 'WordDocument')
    table = stream(data, raw['tableStream'])
    at, size = u32(word, 154 + 15 * 8), u32(word, 158 + 15 * 8)
    fonts, cursor = [], at + 4
    require(u16(table, at + 2) == 0, 'Unexpected extra font bytes')
    for index in range(u16(table, at)):
        length = table[cursor] + 1
        name = table[cursor + 40:cursor + length].decode('utf-16le').split('\0', 1)[0]
        fonts.append(name)
        cursor += length
    require(cursor == at + size and fonts[8] == 'Courier New', 'Source font index 8')
    return {'sourceSha256': SOURCE_SHA256, 'lineNumberStyle': style,
            'fontIndex': 8, 'fontName': fonts[8], 'fontSizeHalfPoints': 28,
            'colorHex': 'CC2233', 'bold': True, 'characterPropertiesHex': props.hex()}
