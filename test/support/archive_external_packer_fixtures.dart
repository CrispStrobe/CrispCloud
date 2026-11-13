import 'dart:convert';
import 'dart:typed_data';

/// Original fixtures generated with the unmodified official RAR 7.23 Linux
/// trial, 2026-11-13. Payload: "Independent RAR5 metadata fixture.\n" repeated
/// 64 times in precise-雪.txt; mode 0640, UTC 2024-01-02 03:04:05.123456.
/// Fixed switches: a -cfg- -ma5 -m3 -s- -r- -mt2 -scfl -tsm+ -tsc- -tsa-.
/// The encrypted variants add -pfixture-pass or -hpfixture-pass. This is an
/// explicit public test password, not an application credential. No vendor
/// binary or proprietary algorithm is redistributed in these fixtures.
const rarMetadataFixturePassword = 'fixture-pass';
final rarMetadataFixtureTime = DateTime.utc(2024, 1, 2, 3, 4, 5, 123, 456);
String get rarMetadataFixtureText =>
    'Independent RAR5 metadata fixture.\n' * 64;

/// SHA-256 7c1aa4003541b6c6c0a5a844c7081a7159ae0e95f3012f714de4767ff4b5380b.
Uint8List rarPlainMetadataFixture() => base64Decode(
  'UmFyIRoHAQDz4YLrCwEFBwAGAQGAgIAA+ej/hy0CAwu6AATAEaCDAoEy6CKAAwEPcHJlY2lzZS3pm6oudHh0CgMTJX2TZQDKWwfCrzckVTL6M73CpgTW4A2NswOBPoNDBEiDv9C4vL/eq7KuOy6zKND+ZyOp0LIdFT0V8dfmxOUHbC8gHXdWUQMFBAA=',
);

/// SHA-256 0bda7b5b2264578351c864a8d2accf070e9ffc8e4c6cf4b729b1daa62c5a7c6b.
Uint8List rarEncryptedMetadataFixture() => base64Decode(
  'UmFyIRoHAQDz4YLrCwEFBwAGAQGAgIAA9vg1K14CAzzAAATAEaCDAqB0Fa2AAwEPcHJlY2lzZS3pm6oudHh0MAEAAw83irmpBTxmtT+i9mhwM3uMwEUTuZF0KPeJIX9EczMqIr4B0OZlhjeKytYT2QoDEyV9k2UAylsHNxm2dNvihrkWg/xATu80RBkmY9fY2IAR9zcN5Mx9CyxWrJ1lA+FJOY1/5tcj3g1zr9n6VrqL0qsgKIjWFbzJYx13VlEDBQQA',
);

/// SHA-256 e9ecef7b917a2493907dec381c9fa58bf8594466871fc342bc2b9b91601a6388.
Uint8List rarHiddenMetadataFixture() => base64Decode(
  'UmFyIRoHAQB8Kjj1IQQAAAEPo2vN3E6G7CXwmeytn3oaiU40Qoatn7pEjNOM3AZv69BG/7A7r/1YwgyEYmuNwHd1U359MfUzpB2vusU8dT51qUYFKkNX82RMZbGOnKpD+YsnyO9+8gELyKigQJh+WiWv/xBEOj0uPViEyxL8+vDDiKl9ykauP6e3HDSNp9lr5WrFKM0seACHgZS1Q2vBy81JT7j2gawRBiR1NbWUNM7Pw11nOQAQ6LAOg4N5jTN6SpE3QzI0G68tV2a/XiCDbgdotlpUXl9g6HOLHmQMY1zCIsO9oiR3bQgYe/IOJB/XhhBpdHnVua1j6ohjieDBoKJ/DLwhatcxaln86vpBuMIr6aFtkJjFIkKMJhrwhGtp8Ux2/2mxK9BYirUpue8=',
);
