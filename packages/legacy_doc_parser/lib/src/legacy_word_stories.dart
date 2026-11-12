// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.3.2–2.3.7 and the referenced PLC definitions. A document-part
// length alone never identifies individual notes, headers, or real textboxes.
class _Plc {
  const _Plc(this.cps, this.data);
  final List<int> cps;
  final _Bytes data;
  int get count => cps.length - 1;
}

extension _WordStories on _StructuredWordParser {
  int _storyBase(int index) {
    var cp = source.bodyLength;
    for (var i = 0; i < index; i++) {
      cp += source.storyLengths[i];
    }
    return cp;
  }

  _Plc? _plc(int pair, int recordSize, int cpLimit, {bool allowEqual = false}) {
    final (offset, length) = source.pair(pair);
    if (length == 0) return null;
    if (length < 4 || (length - 4) % (recordSize + 4) != 0) {
      throw const FormatException('Invalid Word reference table size.');
    }
    final count = (length - 4) ~/ (recordSize + 4);
    if (count > 50000) {
      throw const FormatException(
        'Word references exceed the complexity limit.',
      );
    }
    final input = _Bytes(source.table.slice(offset, length));
    final cps = [for (var i = 0; i <= count; i++) input.u32(i * 4)];
    for (var i = 0; i < count; i++) {
      if (cps[i] > cpLimit ||
          (i > 0 &&
              (allowEqual ? cps[i] < cps[i - 1] : cps[i] <= cps[i - 1]))) {
        throw const FormatException('Word reference positions are invalid.');
      }
    }
    // The final CP is ignored for reference PLCs; callers whose last CP is an
    // actual range endpoint validate that endpoint explicitly.
    return _Plc(cps, _Bytes(input.slice((count + 1) * 4, count * recordSize)));
  }

  List<int> _storyRanges(int pair, int storyLength, {bool allowEmpty = false}) {
    final plc = _plc(pair, 0, storyLength, allowEqual: allowEmpty);
    if (plc == null ||
        plc.cps.length < 2 ||
        plc.cps.first != 0 ||
        plc.cps[plc.cps.length - 2] != storyLength - 1) {
      throw const FormatException(
        'Word story reference ranges are incomplete.',
      );
    }
    return plc.cps.sublist(0, plc.cps.length - 1);
  }

  void _addStory(
    String id,
    LegacyWordStoryKind kind,
    int first,
    int end, {
    int? sectionIndex,
    LegacyWordHeaderFooterType? headerFooterType,
  }) {
    if (stories.length >= 20000 ||
        first < source.bodyLength ||
        end < first ||
        end > body.length) {
      throw const FormatException(
        'Word stories exceed their reference bounds.',
      );
    }
    final blocks = _parseRange(first, end, id);
    stories.add(
      LegacyWordStory(
        id: id,
        kind: kind,
        startCp: first,
        endCp: end,
        blocks: List.unmodifiable(blocks),
        plainText: _plainText(blocks),
        safeHtml: _renderBlocks(blocks),
        sectionIndex: sectionIndex,
        headerFooterType: headerFooterType,
      ),
    );
  }

  void _readAuxiliaryStories() {
    _readNotes(false);
    _readNotes(true);
    _readComments();
    _readHeaders();
    _readTextboxes(false);
    _readTextboxes(true);
  }

  void _resolveReferencePresentations() {
    final storyStarts = {for (final story in stories) story.id: story.startCp};
    LegacyWordMediaPresentation at(int cp) {
      final value = _referencePresentations[cp];
      if (value == null) {
        throw const FormatException('Unresolved Word annotation presentation.');
      }
      return value;
    }

    for (var i = 0; i < noteReferences.length; i++) {
      final old = noteReferences[i];
      noteReferences[i] = LegacyWordNoteReference(
        id: old.id,
        anchorCp: old.anchorCp,
        storyId: old.storyId,
        endnote: old.endnote,
        autoNumbered: old.autoNumbered,
        customMark: old.customMark,
        referenceStyle: _referenceCharacterStyles[old.anchorCp],
        markerStyle: _referenceCharacterStyles[storyStarts[old.storyId]],
        presentation: at(old.anchorCp),
      );
    }
    for (var i = 0; i < commentReferences.length; i++) {
      final old = commentReferences[i];
      commentReferences[i] = LegacyWordCommentReference(
        id: old.id,
        anchorCp: old.anchorCp,
        storyId: old.storyId,
        rangeStartCp: old.rangeStartCp,
        rangeEndCp: old.rangeEndCp,
        author: old.author,
        initials: old.initials,
        time: old.time,
        parentId: old.parentId,
        ink: old.ink,
        sourceRecord: old.sourceRecord,
        presentation: at(old.anchorCp),
      );
    }
  }

  void _readNotes(bool endnote) {
    final storyIndex = endnote ? 3 : 0;
    final length = source.storyLengths[storyIndex];
    final refs = _plc(endnote ? 46 : 2, 2, source.bodyLength);
    if (length == 0) {
      if (refs != null && refs.count != 0) {
        throw const FormatException('Word note references have no note story.');
      }
      return;
    }
    final ranges = _storyRanges(endnote ? 47 : 3, length);
    if (refs == null || refs.count != ranges.length - 1) {
      throw const FormatException(
        'Word note references do not match their text ranges.',
      );
    }
    final base = _storyBase(storyIndex);
    for (var i = 0; i < refs.count; i++) {
      final anchor = refs.cps[i],
          start = base + ranges[i],
          end = base + ranges[i + 1];
      // Some native DOC exporters place the final note boundary on its table
      // terminating mark, immediately before the guard CR. MS-DOC PlcffndTxt
      // normally requires CR. Recover only this closed table, never an arbitrary
      // unterminated paragraph or a range reaching into the following story.
      final tableBoundary =
          end > start &&
          end == base + length - 1 &&
          body[end - 1] == 7 &&
          body[end] == 13;
      if (anchor >= source.bodyLength ||
          end <= start ||
          (body[end - 1] != 13 && !tableBoundary)) {
        throw const FormatException(
          'Invalid Word note reference or terminator.',
        );
      }
      final autoNumbered = refs.data.u16(i * 2) != 0;
      if (autoNumbered && body[anchor] != 2) {
        throw const FormatException(
          'Word note reference does not match its marker.',
        );
      }
      final id = i + 1, storyId = '${endnote ? 'endnote' : 'footnote'}-$id';
      _noteMarkerCps.add(anchor);
      _referenceAnchors.add(anchor);
      if (body[start] == 2) {
        _noteMarkerCps.add(start);
        _referenceAnchors.add(start);
      }
      noteReferences.add(
        LegacyWordNoteReference(
          id: id,
          anchorCp: anchor,
          storyId: storyId,
          endnote: endnote,
          autoNumbered: autoNumbered,
          customMark: autoNumbered ? null : String.fromCharCode(body[anchor]),
        ),
      );
      _addStory(
        storyId,
        endnote ? LegacyWordStoryKind.endnote : LegacyWordStoryKind.footnote,
        start,
        end,
      );
      if (tableBoundary) {
        final blocks = stories.last.blocks;
        if (blocks.isEmpty ||
            blocks.last is! LegacyWordTable ||
            blocks.last.endCp != end) {
          throw const FormatException('Unclosed Word table at note boundary.');
        }
        warnings.add(LegacyWordWarning.recoveredTableStoryBoundary);
      }
    }
  }

  void _readHeaders() {
    final length = source.storyLengths[1];
    if (length == 0) return;
    final ranges = _storyRanges(11, length, allowEmpty: true);
    if (ranges.length - 1 != 6 + sections.length * 6) {
      throw const FormatException(
        'Word header stories do not match the sections.',
      );
    }
    final base = _storyBase(1);
    const separators = [
      LegacyWordStoryKind.footnoteSeparator,
      LegacyWordStoryKind.footnoteContinuationSeparator,
      LegacyWordStoryKind.footnoteContinuationNotice,
      LegacyWordStoryKind.endnoteSeparator,
      LegacyWordStoryKind.endnoteContinuationSeparator,
      LegacyWordStoryKind.endnoteContinuationNotice,
    ];
    for (var i = 0; i < ranges.length - 1; i++) {
      final first = base + ranges[i], guardEnd = base + ranges[i + 1];
      if (first == guardEnd) {
        continue; // Empty slots inherit the preceding section.
      }
      if (body[guardEnd - 1] != 13) {
        throw const FormatException('Word header has no guard paragraph mark.');
      }
      final end = guardEnd - 1;
      if (i < 6) {
        _addStory(separators[i].name, separators[i], first, end);
        continue;
      }
      if (end <= first || body[end - 1] != 13) {
        throw const FormatException(
          'Word header content is not a complete paragraph.',
        );
      }
      final section = (i - 6) ~/ 6, slot = (i - 6) % 6;
      final header = slot == 0 || slot == 1 || slot == 4;
      final type = slot < 4
          ? (slot.isEven
                ? LegacyWordHeaderFooterType.even
                : LegacyWordHeaderFooterType.normal)
          : LegacyWordHeaderFooterType.first;
      final kind = header
          ? LegacyWordStoryKind.header
          : LegacyWordStoryKind.footer;
      _addStory(
        '${kind.name}-$section-${type.name}',
        kind,
        first,
        end,
        sectionIndex: section,
        headerFooterType: type,
      );
    }
  }

  void _readComments() {
    final length = source.storyLengths[2];
    final refs = _plc(4, 30, source.bodyLength);
    if (length == 0) {
      if (refs != null && refs.count != 0) {
        throw const FormatException('Word comments have no text story.');
      }
      return;
    }
    final ranges = _storyRanges(5, length);
    if (refs == null || refs.count != ranges.length - 1) {
      throw const FormatException(
        'Word comment references do not match their text.',
      );
    }
    final owners = <String>[];
    final (ownersOffset, ownersLength) = source.pair(36);
    final ownerData = _Bytes(source.table.slice(ownersOffset, ownersLength));
    var cursor = 0;
    while (cursor < ownerData.length) {
      final size = ownerData.u16(cursor);
      cursor += 2;
      if (size >= 56 || owners.length >= 32767) {
        throw const FormatException('Invalid Word comment author table.');
      }
      owners.add(_unicodeString(ownerData, cursor, size));
      cursor += size * 2;
    }
    final annotationRanges = _annotationBookmarks();
    final (extraOffset, extraLength) = source.pair(112);
    _Bytes? extra;
    if (extraLength != 0) {
      if (extraLength != refs.count * 18) {
        throw const FormatException('Invalid Word extended comment records.');
      }
      extra = _Bytes(source.table.slice(extraOffset, extraLength));
      final ancestors = <int>[];
      for (var i = 0; i < refs.count; i++) {
        final depth = extra.u32(i * 18 + 6),
            relativeParent = extra.i32(i * 18 + 10);
        if (depth > 64 ||
            depth > ancestors.length ||
            (depth == 0 && relativeParent != 0) ||
            (depth != 0 &&
                (relativeParent >= 0 ||
                    i + relativeParent != ancestors[depth - 1] ||
                    extra.u32((i + relativeParent) * 18 + 6) + 1 != depth))) {
          throw const FormatException(
            'Invalid Word comment-parent relationship.',
          );
        }
        ancestors.length = depth;
        ancestors.add(i);
      }
    }
    final base = _storyBase(2);
    for (var i = 0; i < refs.count; i++) {
      final anchor = refs.cps[i],
          first = base + ranges[i],
          end = base + ranges[i + 1];
      if (anchor >= source.bodyLength ||
          body[anchor] != 5 ||
          first >= end ||
          body[first] != 5 ||
          body[end - 1] != 13) {
        throw const FormatException(
          'Word comment markers do not match their references.',
        );
      }
      final record = i * 30, initialsLength = refs.data.u16(record);
      if (initialsLength > 9) {
        throw const FormatException('Invalid Word comment initials.');
      }
      final author = refs.data.u16(record + 20);
      if (author >= owners.length) {
        throw const FormatException('Missing Word comment author.');
      }
      final tag = refs.data.i32(record + 26);
      final range = annotationRanges[tag];
      if (tag != -1 && range == null) {
        throw const FormatException('Missing Word comment range.');
      }
      final id = 'comment-$i';
      _commentMarkerCps.addAll([anchor, first]);
      _referenceAnchors.add(anchor);
      commentReferences.add(
        LegacyWordCommentReference(
          id: i,
          anchorCp: anchor,
          storyId: id,
          rangeStartCp: range?.$1,
          rangeEndCp: range?.$2,
          author: owners[author],
          initials: _unicodeString(refs.data, record + 2, initialsLength),
          time: extra == null ? null : _revisionDate(extra.u32(i * 18)),
          parentId: extra == null || extra.u32(i * 18 + 6) == 0
              ? null
              : i + extra.i32(i * 18 + 10),
          ink: extra != null && (extra.u32(i * 18 + 14) & 2) != 0,
          sourceRecord: extra == null
              ? null
              : LegacyWordCommentSourceRecord(
                  bytes: extra.slice(i * 18, 18),
                  tableOffset: extraOffset + i * 18,
                ),
        ),
      );
      _addStory(id, LegacyWordStoryKind.comment, first, end);
    }
  }

  void _readTextboxes(bool header) {
    final index = header ? 5 : 4, length = source.storyLengths[header ? 5 : 4];
    if (length == 0) return;
    final plc = _plc(header ? 58 : 56, 22, length);
    if (plc == null ||
        plc.count < 1 ||
        plc.cps.first != 0 ||
        plc.cps.last > length) {
      throw const FormatException('Missing or invalid Word textbox ranges.');
    }
    final anchorLength = header ? source.storyLengths[1] : source.bodyLength;
    final anchorBase = header ? _storyBase(1) : 0;
    final anchors = _plc(header ? 41 : 40, 26, anchorLength);
    final byShape = <int, int>{};
    if (anchors != null) {
      for (var i = 0; i < anchors.count; i++) {
        final shape = anchors.data.u32(i * 26);
        if (byShape.containsKey(shape)) {
          throw const FormatException('Ambiguous Word shape anchor.');
        }
        byShape[shape] = anchorBase + anchors.cps[i];
      }
    }
    final base = _storyBase(index);
    for (var i = 0; i < plc.count - 1; i++) {
      final first = base + plc.cps[i], end = base + plc.cps[i + 1];
      final reusable = plc.data.u16(i * 22 + 8);
      if (reusable != 0) {
        if ((reusable & 1) == 0 || end - first != 1) {
          throw const FormatException('Invalid reusable Word textbox.');
        }
        continue; // The text belongs to an unused spare record, not a textbox.
      }
      if (end - first < 2 || body[end - 1] != 13) {
        throw const FormatException('Invalid Word textbox content range.');
      }
      final shape = plc.data.u32(i * 22 + 14), count = plc.data.u32(i * 22);
      if (count == 0 || count > 4096 || !byShape.containsKey(shape)) {
        throw const FormatException('Unresolved Word textbox shape reference.');
      }
      if (count > 1) warnings.add(LegacyWordWarning.unsupportedFormatting);
      final id = '${header ? 'header-textbox' : 'textbox'}-${i + 1}';
      textboxReferences.add(
        LegacyWordTextboxReference(
          id: i + 1,
          storyId: id,
          inHeaderFooter: header,
          anchorCp: byShape[shape],
          shapeId: shape,
          chainLength: count,
        ),
      );
      _addStory(
        id,
        header
            ? LegacyWordStoryKind.headerTextbox
            : LegacyWordStoryKind.textbox,
        first,
        end,
      );
    }
  }

  void _linkTextboxDrawings(LegacyWordMediaCatalog media) {
    final references = <(bool, int), int>{};
    final links = <(bool, int), List<LegacyWordTextboxAnchor>>{};
    for (var i = 0; i < textboxReferences.length; i++) {
      final reference = textboxReferences[i];
      references[(reference.inHeaderFooter, reference.id)] = i;
    }
    final used = <(bool, int, int)>{};
    for (final drawing in media.drawings) {
      final encoded = drawing.textboxId;
      if (encoded == null || encoded == 0) continue;
      final id = encoded >> 16, chainIndex = encoded & 0xffff;
      final key = (drawing.headerStory, id);
      final index = references[key];
      if (index == null ||
          chainIndex >= textboxReferences[index].chainLength ||
          !used.add((drawing.headerStory, id, chainIndex))) {
        throw const FormatException(
          'Invalid Word drawing-to-textbox reference.',
        );
      }
      final reference = textboxReferences[index];
      if (chainIndex == 0 && reference.shapeId != drawing.shapeId) {
        throw const FormatException(
          'Word textbox first-shape references do not agree.',
        );
      }
      links
          .putIfAbsent(key, () => [])
          .add(
            LegacyWordTextboxAnchor(
              shapeId: drawing.shapeId,
              anchorCp: drawing.anchorCp,
              chainIndex: chainIndex,
              nextShapeId: drawing.nextTextboxShapeId,
            ),
          );
    }
    for (final entry in links.entries) {
      final index = references[entry.key]!;
      final reference = textboxReferences[index];
      final anchors = entry.value
        ..sort((a, b) => a.chainIndex.compareTo(b.chainIndex));
      if (anchors.length != reference.chainLength ||
          anchors.first.chainIndex != 0) {
        throw const FormatException('Incomplete Word textbox shape chain.');
      }
      for (var i = 0; i < anchors.length; i++) {
        final next = anchors[i].nextShapeId;
        if (next == null || next == 0) continue;
        if (i + 1 >= anchors.length || next != anchors[i + 1].shapeId) {
          throw const FormatException('Invalid Word textbox next-shape chain.');
        }
      }
      textboxReferences[index] = LegacyWordTextboxReference(
        id: reference.id,
        storyId: reference.storyId,
        inHeaderFooter: reference.inHeaderFooter,
        anchorCp: reference.anchorCp,
        shapeId: reference.shapeId,
        chainLength: reference.chainLength,
        anchors: List.unmodifiable(anchors),
      );
    }
  }

  String _unicodeString(_Bytes bytes, int at, int count) {
    bytes.require(at, count * 2);
    final units = [for (var i = 0; i < count; i++) bytes.u16(at + 2 * i)];
    _validateUnicode(units);
    return String.fromCharCodes(units);
  }

  List<(int, int, int)> _bookmarkRanges(int startPair, int endPair, int limit) {
    final starts = _plc(startPair, 4, limit, allowEqual: true);
    final ends = _plc(endPair, 0, limit, allowEqual: true);
    if (starts == null && ends == null) return const [];
    if (starts == null || ends == null || starts.count != ends.count) {
      throw const FormatException('Word bookmark tables do not match.');
    }
    final used = <int>{}, output = <(int, int, int)>[];
    for (var i = 0; i < starts.count; i++) {
      final endIndex = starts.data.u16(i * 4);
      if (endIndex >= ends.count || !used.add(endIndex)) {
        throw const FormatException('Invalid Word bookmark-end reference.');
      }
      final first = starts.cps[i], end = ends.cps[endIndex];
      if (end < first) {
        throw const FormatException('Reversed Word bookmark range.');
      }
      output.add((first, end, starts.data.u16(i * 4 + 2)));
    }
    return output;
  }

  void _readBookmarks() {
    final ranges = _bookmarkRanges(22, 23, body.length);
    final (offset, length) = source.pair(21);
    if (length == 0) {
      if (ranges.isNotEmpty) {
        throw const FormatException('Word bookmark names are missing.');
      }
      return;
    }
    final input = _Bytes(source.table.slice(offset, length));
    if (input.u16(0) != 0xffff ||
        input.u16(4) != 0 ||
        input.u16(2) != ranges.length ||
        ranges.length > 0x3ffc) {
      throw const FormatException('Invalid Word bookmark name table.');
    }
    var cursor = 6;
    final names = <String>{};
    for (final (first, end, flags) in ranges) {
      final count = input.u16(cursor);
      cursor += 2;
      if (count == 0 || count > 40) {
        throw const FormatException('Invalid Word bookmark name length.');
      }
      final name = _unicodeString(input, cursor, count);
      cursor += count * 2;
      if (!names.add(name)) {
        throw const FormatException('Duplicate Word bookmark name.');
      }
      final column = (flags & 0x8000) != 0;
      final firstCell = flags & 0x7f;
      final limitCell = (flags >> 8) & 0x3f;
      if (column && firstCell >= limitCell) {
        throw const FormatException('Invalid Word column bookmark range.');
      }
      bookmarks.add(
        LegacyWordBookmark(
          name: name,
          startCp: first,
          endCp: end,
          firstCell: column ? firstCell : null,
          lastCell: column ? limitCell - 1 : null,
        ),
      );
    }
    if (cursor != length) {
      throw const FormatException('Unexpected Word bookmark data.');
    }
  }

  void _validateBookmarkStories() {
    final ordered = [...stories]
      ..sort((a, b) => a.startCp.compareTo(b.startCp));
    for (final bookmark in bookmarks) {
      if (bookmark.endCp <= source.bodyLength) continue;
      var low = 0, high = ordered.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (ordered[middle].startCp <= bookmark.startCp) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      if (low == 0 || bookmark.endCp > ordered[low - 1].endCp) {
        throw const FormatException(
          'Word bookmark crosses or misses a referenced story.',
        );
      }
    }
  }

  Map<int, (int, int)> _annotationBookmarks() {
    final ranges = _bookmarkRanges(42, 43, source.bodyLength);
    final (offset, length) = source.pair(37);
    if (length == 0) {
      if (ranges.isNotEmpty) {
        throw const FormatException('Word comment bookmark tags are missing.');
      }
      return const {};
    }
    final input = _Bytes(source.table.slice(offset, length));
    if (input.u16(0) != 0xffff ||
        input.u16(4) != 10 ||
        input.u16(2) != ranges.length ||
        length != 6 + ranges.length * 12) {
      throw const FormatException('Invalid Word comment bookmark table.');
    }
    final result = <int, (int, int)>{};
    for (var i = 0; i < ranges.length; i++) {
      final at = 6 + i * 12;
      if (input.u16(at) != 0 || input.u16(at + 2) != 0x100) {
        throw const FormatException('Invalid Word comment bookmark class.');
      }
      final tag = input.i32(at + 4);
      if (result.containsKey(tag)) {
        throw const FormatException('Duplicate Word comment bookmark tag.');
      }
      result[tag] = (ranges[i].$1, ranges[i].$2);
    }
    return result;
  }
}
