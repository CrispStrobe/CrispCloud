# Canonical compatibility and incoming parser merge

This checkpoint combines compatibility branch `e4427725cc720eaefad97c2cb921a6fe1e36749d` with parser source `d9f640693702d59470d74c56db7ebadb1bab5b10`, the exact source pin used by incoming CrispCloud main `07928e070135d422fbd136fccd1bf53d0d2d47b6`. The common ancestor is `419864b3076cea56f3f4d170a3ace88cfc397027`. Both parents remain in the merge ancestry. No later main revision is included.

## Preserved behavior

The merge retains the compatibility recovery changes for bounded legacy linked-picture records, inert external references, unpositioned textbox stories, and corroborated nil table borders. It also retains the incoming textbox bitmap/pattern/gradient fill handling, validated DIB wrapping, image embedding bytes, textbox width handling, ink transform/pressure metrics, and their fixtures and independent native evidence.

Git merged without conflicts. The three overlapping source files were reviewed together: `legacy_word_media_model.dart`, `legacy_word_media_parser.dart`, and `word_media_writer.dart`. No additional parser behavior was introduced to resolve this merge.

## Validation of the combined source

- `dart analyze`: no issues.
- Focused compatibility, textbox, OfficeArt, shape-context, ink, and sizing regressions: **145 tests passed**.
- Complete `dart test --reporter expanded`: **1,055 tests passed**.
- `python3 tool/verify_web.py`: Dart-to-JavaScript compilation and Node acceptance passed. This includes DOC stories, Unicode, images, metadata and source immutability; 51 metafile/media checks; 24 ink cases; and 32 ink-header cases.
- `dart format --output=none --set-exit-if-changed .`: passed, 210 files and zero changes after formatting the historical probe helper.

The formatter gate required a formatting-only normalization of `../file-viewer-compat-20261113/native_probe.dart`. Its historical result, provenance, fixture manifest, and source-hash files are unchanged. The original helper bytes remain available in the first parent.

`validation.json` records the exact source hashes, `lib` Git tree, commands, passing counts, and archive hashes. `validation-logs.tar.xz` contains the complete command logs with deterministic archive metadata.

## Scope of this evidence

The checks here exercise the combined parser source in Dart and compiled JavaScript. They do not claim a new native Microsoft Word, LibreOffice, or WPF run. Retained native receipts and the earlier 19-document comparison continue to describe their recorded revisions. This branch is a review candidate; neither parser main nor the app main branch is changed by this checkpoint.
