# Independent DMG compression fixtures

`apple-hdiutil.adc` and `apple-hdiutil.bin` are unchanged from
[go-compressions/adc at 3dbe1889](https://github.com/go-compressions/adc/tree/3dbe188981fa046d9b58696ba6e034c6b68b57a6/testdata).
The upstream author records producing the compressed stream with Apple's
`hdiutil convert -format UDCO`. Its 1,260 encoded bytes exercise all three ADC
token forms and expand to 4,096 bytes. Retained BSD-3-Clause terms are in
`LICENSE-adc-fixture`, including the upstream copyright spelling unchanged.
These files are test inputs, not shipped application assets.

The `liblzma*` files were generated independently of the Dart implementation
with Python's liblzma-backed `lzma` module:

```python
raw = bytes((i * 7 + i // 23) % 251 for i in range(4096))
packed = lzma.compress(raw, format=lzma.FORMAT_XZ,
    check=lzma.CHECK_CRC64,
    filters=[{'id': lzma.FILTER_LZMA2, 'dict_size': dictionary}])
```

`dictionary` is 1 MiB for the positive fixture and 32 MiB for the resource-limit
refusal fixture. Each compressed stream has 468 bytes. The fixture content is
authored for these tests; no production image is included.

| File | SHA-256 |
| --- | --- |
| apple-hdiutil.adc | d612e50a80d45d88230a1a61393e5411d46db293c6a40ec31f341fca628f53cb |
| apple-hdiutil.bin | bab30ffadc30ac40a01be8f171e92c68a49d76d3e445bba132346c8f31f14b32 |
| liblzma-1m.xz | 7bb1c196e899b2eb0e04933054a9a836a28f6003876ca99cee2dfc45f9551a29 |
| liblzma-32m.xz | 89b2e27b21bcb5541447d0ca274835b49e0f24caf4b32c2cb4817c74373df92a |
| liblzma.bin | 4c035498e45cb143e68b1f84a193234dc4b8975c1e5a569fc0212ec210818468 |
