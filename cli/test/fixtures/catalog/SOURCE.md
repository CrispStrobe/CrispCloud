# Independent Catfish CAF fixture

`catfish-v8-windows.caf` was authored by the unchanged Python
`FileIndex._write_caf` at Catfish commit
`b4aa7b8a960bb74dcfd313719017dd0a739654a7` (`core/file_index.py`, MIT).
It has root `C:\Archive`, one directory `folder`, and three files:
`folder/nine.bin` (9 bytes), `café.txt` (3), `zero.txt` (0), all with
mtime 1700000000. The directory has mtime 1700000000. Input ELM records:
`[(1700000000,-1,0,'folder'), (1700000000,9,1,'nine.bin'),
(1700000000,0,0,'zero.txt'), (1700000000,3,0,'café.txt')]`.
Info records: `[(0,3,12), (1,1,9)]`.

SHA-256: `b227276bebe23a180a47914de95ef95e19fbcc84b001456ba256a9970b0561eb`.
No real user files or credentials are included. The independent fixture catches
Windows-path, Latin-1 and modern zero-byte regressions across the Rust/Dart API.
