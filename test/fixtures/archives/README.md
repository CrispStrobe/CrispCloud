# Archive test fixtures

Small archives used by the viewer's unit and live tests.

| File | Origin | Contents |
| --- | --- | --- |
| `sample.7z` | [`koni_archive`](https://github.com/zenbaku/koni_archive) → `koni_sevenz/test/fixtures/sevenz/delta_lzma2.7z` | `nested/deep/data.bin` (100,000 bytes), delta + LZMA2 |
| `deflate.7z` | same repository → `koni_sevenz/test/fixtures/sevenz/deflate.7z` | multiple entries incl. UTF-8 names (`日本語/ページ001.txt`) |
| `encrypted.7z` | same repository → `koni_sevenz/test/fixtures/sevenz/encrypted.7z` | AES-256 entries, password `secret`, `hello.txt` |
| `header_encrypted.7z` | same repository → `koni_sevenz/test/fixtures/sevenz/encrypted_header.7z` | AES-256 with encrypted header (`-mhe`), password `secret` |
| `bcj2.7z` | same repository → `koni_sevenz/test/fixtures/sevenz/bcj2.7z` | uses an unsupported BCJ2 codec (typed error path) |
| `sample.rar` | same repository → `koni_rar/test/fixtures/rar_static/filter_delta.rar` | RAR4, delta filter, `grad.bmp` (27,702 bytes) |
| `encrypted.rar` | same repository → `koni_rar/test/fixtures/rar_static/enc_rar4.rar` | RAR4 encrypted, password `secret` |

## License

`koni_archive` and its format packages are MIT licensed:

```
MIT License

Copyright (c) 2026 the koni_archive authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

The fixtures are redistributed unmodified for interoperability testing only.
