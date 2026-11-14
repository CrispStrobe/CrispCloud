// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

class _WordInlineEvent {
  const _WordInlineEvent(
    this.cp,
    this.order,
    this.write, {
    this.closing = false,
  });
  final int cp;
  final int order;
  final void Function() write;
  final bool closing;
}

extension _WordStories on _StructuredWordWriter {
  int get _mainEnd => document.blocks.isEmpty
      ? (document.sections.isEmpty ? 0 : document.sections.last.endCp)
      : document.blocks.last.endCp;

  void _prepareStories() {
    if (document.stories.length > 4096 ||
        document.fields.length > 20000 ||
        document.bookmarks.length > 20000 ||
        document.numbering.length > 4096) {
      _tooComplex();
    }
    final hidden = <(int, int)>[];
    for (final field in document.fields) {
      final separator = field.separatorCp ?? field.endCp - 1;
      hidden.add((field.startCp + 1, separator));
      if (field.privateResult && field.separatorCp != null) {
        hidden.add((field.separatorCp! + 1, field.endCp - 1));
      }
    }
    hidden.sort((a, b) => a.$1.compareTo(b.$1));
    for (final range in hidden) {
      if (range.$2 <= range.$1) continue;
      if (_hiddenContentRanges.isNotEmpty &&
          _hiddenContentRanges.last.$2 >= range.$1) {
        final prior = _hiddenContentRanges.removeLast();
        _hiddenContentRanges.add((
          prior.$1,
          prior.$2 > range.$2 ? prior.$2 : range.$2,
        ));
      } else {
        _hiddenContentRanges.add(range);
      }
    }
    _storyRanges.add((0, _mainEnd, 'main'));
    var header = 0, footer = 0;
    for (final story in document.stories) {
      if (story.id == 'main' ||
          _stories.containsKey(story.id) ||
          story.startCp < 0 ||
          story.endCp < story.startCp) {
        throw const FormatException('Invalid Word story identity or range.');
      }
      _stories[story.id] = story;
      _storyRanges.add((story.startCp, story.endCp, story.id));
      if (story.kind == LegacyWordStoryKind.header ||
          story.kind == LegacyWordStoryKind.footer) {
        final isHeader = story.kind == LegacyWordStoryKind.header;
        final number = isHeader ? ++header : ++footer;
        final name = '${isHeader ? 'header' : 'footer'}$number.xml';
        _storyParts[story.id] = 'word/$name';
        final relation = _package.relate(
          'word/document.xml',
          '$_relationshipNamespace/${isHeader ? 'header' : 'footer'}',
          name,
        );
        final section = story.sectionIndex ?? 0;
        if (section < 0 ||
            section >=
                (document.sections.isEmpty ? 1 : document.sections.length)) {
          throw const FormatException('Invalid Word header section reference.');
        }
        final type = switch (story.headerFooterType) {
          LegacyWordHeaderFooterType.even => 'even',
          LegacyWordHeaderFooterType.first => 'first',
          _ => 'default',
        };
        final references = _headerFooters.putIfAbsent(section, () => []);
        if (references.any(
          (entry) => entry.$1 == isHeader && entry.$2 == type,
        )) {
          throw const FormatException('Duplicate Word header or footer.');
        }
        references.add((isHeader, type, relation));
      }
    }
    _storyRanges.sort((a, b) => a.$1.compareTo(b.$1));
    var end = -1;
    for (final range in _storyRanges) {
      if (range.$1 < end) {
        throw const FormatException('Overlapping Word stories.');
      }
      end = range.$2;
    }
    for (final definition in document.numbering) {
      if (definition.id <= 0 ||
          definition.levels.isEmpty ||
          definition.levels.length > 9 ||
          !_numberingIds.add(definition.id)) {
        throw const FormatException('Invalid Word numbering definition.');
      }
    }
    final definitions = {
      for (final value in document.numbering) value.id: value,
    };
    for (final definition in document.numbering) {
      final targetId = definition.continuationOf;
      if (targetId != null) {
        final target = definitions[targetId];
        if (target == null ||
            target.id == definition.id ||
            target.continuationOf != null ||
            target.sourceListId == null ||
            target.sourceListId != definition.sourceListId ||
            target.levels.length != definition.levels.length ||
            !List.generate(
              target.levels.length,
              (i) => identical(target.levels[i], definition.levels[i]),
            ).every((v) => v)) {
          throw const FormatException('Invalid Word numbering continuation.');
        }
        _evidenceRecords.add({
          'kind': 'numberingContinuation',
          'sourceIlfo': definition.id,
          'sourceLsid': definition.sourceListId,
          'nativeNumId': targetId,
        });
      }
      _numberingReferences[definition.id] = targetId ?? definition.id;
    }
  }

  String? _storyAt(int cp) {
    var low = 0, high = _storyRanges.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final range = _storyRanges[middle];
      if (cp < range.$1) {
        high = middle;
      } else if (cp >= range.$2) {
        low = middle + 1;
      } else {
        return range.$3;
      }
    }
    return cp == _mainEnd && _mainEnd == 0 ? 'main' : null;
  }

  bool _displayPosition(int cp) {
    var low = 0, high = _hiddenContentRanges.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final range = _hiddenContentRanges[middle];
      if (cp < range.$1) {
        high = middle;
      } else if (cp >= range.$2) {
        low = middle + 1;
      } else {
        return false;
      }
    }
    return true;
  }

  void _event(
    String story,
    int cp,
    int order,
    void Function() write, {
    bool closing = false,
  }) {
    if (++_inlineEventCount > 100000) _tooComplex();
    final start = story == 'main' ? 0 : _stories[story]?.startCp;
    final end = story == 'main' ? _mainEnd : _stories[story]?.endCp;
    if (start == null || end == null || cp < start || cp > end) {
      throw const FormatException(
        'A Word content reference is outside its story.',
      );
    }
    _events
        .putIfAbsent(story, () => [])
        .add(_WordInlineEvent(cp, order, write, closing: closing));
  }

  void _sortEvents() {
    for (final events in _events.values) {
      events.sort((a, b) {
        final cp = a.cp.compareTo(b.cp);
        return cp != 0 ? cp : a.order.compareTo(b.order);
      });
    }
  }

  void _emitEventsThrough(int cp) {
    final events = _events[_storyId];
    if (events == null) return;
    var index = _eventOffsets[(_storyId, _part)] ?? 0;
    while (index < events.length && events[index].cp <= cp) {
      final event = events[index++];
      _eventOffsets[(_storyId, _part)] = index;
      event.write();
    }
  }

  void _emitBoundaryClosures(int cp) {
    final events = _events[_storyId];
    if (events == null) return;
    var index = _eventOffsets[(_storyId, _part)] ?? 0;
    while (index < events.length &&
        events[index].cp == cp &&
        events[index].closing) {
      final event = events[index++];
      _eventOffsets[(_storyId, _part)] = index;
      event.write();
    }
  }

  void _finishStoryEvents() {
    final events = _events[_storyId];
    if (events == null ||
        (_eventOffsets[(_storyId, _part)] ?? 0) == events.length) {
      return;
    }
    _xml.add('<w:p');
    _commentParagraphAttribute();
    _xml.add('>');
    _emitEventsThrough(
      _storyId == 'main' ? _mainEnd : _stories[_storyId]!.endCp,
    );
    _xml.add('</w:p>');
  }

  void _run(LegacyWordRun run) {
    if (run.endCp - run.startCp != run.text.length) {
      throw const FormatException('Word run positions do not match text.');
    }
    if (run.startCp < run.endCp) {
      // The normalized public model contains display runs only: the parser
      // flushes and skips instruction/private-result units. Recheck callers'
      // spans against the merged field ranges before emitting any text or
      // events. Checking only the start misses a run crossing a hidden range.
      var low = 0, high = _hiddenContentRanges.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (_hiddenContentRanges[middle].$2 <= run.startCp) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      if (low < _hiddenContentRanges.length &&
          _hiddenContentRanges[low].$1 < run.endCp) {
        throw const FormatException(
          'Word display run overlaps field instructions or private results.',
        );
      }
    }
    _emitEventsThrough(run.startCp);
    var position = run.startCp;
    final events = _events[_storyId] ?? const <_WordInlineEvent>[];
    while (position < run.endCp) {
      final index = _eventOffsets[(_storyId, _part)] ?? 0;
      final boundary = index < events.length && events[index].cp < run.endCp
          ? events[index].cp
          : run.endCp;
      if (boundary < position) {
        throw const FormatException('Unordered Word references.');
      }
      if (boundary > position) {
        final start = position - run.startCp, end = boundary - run.startCp;
        if (end < run.text.length &&
            run.text.codeUnitAt(end) >= 0xdc00 &&
            run.text.codeUnitAt(end) <= 0xdfff) {
          throw const FormatException(
            'A Word reference splits a Unicode character.',
          );
        }
        _writeRun(
          LegacyWordRun(
            startCp: position,
            endCp: boundary,
            text: run.text.substring(start, end),
            style: run.style,
            inserted: run.inserted,
            deleted: run.deleted,
            revisionAuthor: run.revisionAuthor,
            revisionTime: run.revisionTime,
            insertionRevision: run.insertionRevision,
            deletionRevision: run.deletionRevision,
            formattingRevision: run.formattingRevision,
            formattingSaveId: run.formattingSaveId,
            symbol: run.symbol,
          ),
        );
      }
      position = boundary;
      if (position < run.endCp) _emitEventsThrough(position);
    }
  }

  void _prepareSemantics() {
    for (final artifact in document.media.artifacts) {
      final cp = artifact.source.cp;
      if (artifact.kind == LegacyWordArtifactKind.binaryData && cp != null) {
        // An ambiguous occurrence must not authorize field metadata removal.
        _fieldBinaryData[cp] = _fieldBinaryData.containsKey(cp)
            ? null
            : artifact;
      }
    }
    final bookmarkNames = <String>{};
    var bookmarkId = 0;
    for (final bookmark in document.bookmarks) {
      // A terminal point in the main body belongs to main even when the next
      // story starts at that CP, matching the parser's bookmark ownership.
      String? story;
      if (bookmark.startCp >= 0 && bookmark.endCp <= _mainEnd) {
        story = 'main';
      } else {
        // Bookmark positions are boundaries, not character anchors. The
        // latest story starting at/before the boundary wins, including its
        // terminal point when no following story begins at the same CP.
        var low = 0, high = _storyRanges.length;
        while (low < high) {
          final middle = (low + high) ~/ 2;
          if (_storyRanges[middle].$1 <= bookmark.startCp) {
            low = middle + 1;
          } else {
            high = middle;
          }
        }
        if (low > 0) story = _storyRanges[low - 1].$3;
      }
      final storyEnd = story == 'main' ? _mainEnd : _stories[story]?.endCp;
      final first = bookmark.firstCell, last = bookmark.lastCell;
      // BKC's six-bit exclusive column limit becomes an inclusive 0..62
      // interval. Word's native bookmark name limit is 40 UTF-16 units.
      if (story == null ||
          storyEnd == null ||
          bookmark.endCp < bookmark.startCp ||
          bookmark.endCp > storyEnd ||
          bookmark.name.isEmpty ||
          bookmark.name.length > 40 ||
          !bookmarkNames.add(bookmark.name) ||
          (first == null) != (last == null) ||
          (first != null && (first < 0 || last! < first || last > 62))) {
        throw const FormatException('Invalid Word bookmark.');
      }
      // Inert bookmarks must satisfy the same Unicode/XML attribute contract.
      // Do not narrow international names to an invented ASCII grammar.
      _BoundedWordXml().text(bookmark.name, attribute: true);
      if (!_displayPosition(bookmark.startCp) ||
          !_displayPosition(
            bookmark.endCp > bookmark.startCp
                ? bookmark.endCp - 1
                : bookmark.endCp,
          )) {
        _evidenceRecords.add({
          'kind': 'bookmark',
          'name': bookmark.name,
          'startCp': bookmark.startCp,
          'endCp': bookmark.endCp,
          if (first != null) 'firstCell': first,
          if (last != null) 'lastCell': last,
          'reason':
              'inert; a boundary is inside field instructions or a private result',
        });
        limitations.add(LegacyWordConversionLimitation.fieldsLists);
        continue;
      }
      final id = bookmarkId++;
      _event(story, bookmark.startCp, 20, () {
        _xml.add('<w:bookmarkStart w:id="$id" w:name="');
        _xml.text(bookmark.name, attribute: true);
        _xml.add('"');
        if (bookmark.firstCell != null) {
          _xml.add(' w:colFirst="${bookmark.firstCell}"');
        }
        if (bookmark.lastCell != null) {
          _xml.add(' w:colLast="${bookmark.lastCell}"');
        }
        _xml.add('/>');
        _count('bookmarks');
      });
      _event(
        story,
        bookmark.endCp,
        bookmark.endCp == bookmark.startCp ? 21 : 0,
        () => _xml.add('<w:bookmarkEnd w:id="$id"/>'),
        closing: true,
      );
    }
    final noteIds = <(bool, int)>{};
    final noteStories = <String>{};
    for (final reference in document.noteReferences) {
      final story = _stories[reference.storyId];
      final kind = reference.endnote
          ? LegacyWordStoryKind.endnote
          : LegacyWordStoryKind.footnote;
      // Hidden notes still own their identity and source position. A shared
      // story can otherwise be made inert after a visible reference has been
      // queued, leaving an active reference with no corresponding note part.
      if (reference.id < 1 ||
          story == null ||
          story.kind != kind ||
          !noteIds.add((reference.endnote, reference.id)) ||
          !noteStories.add(reference.storyId)) {
        throw const FormatException('Invalid Word note reference.');
      }
      final owner = _storyAt(reference.anchorCp);
      if (owner == null) {
        throw const FormatException('Invalid Word note anchor.');
      }
      if (!_displayPosition(reference.anchorCp) ||
          reference.presentation.hidden) {
        _inertStories[story.id] =
            'note marker hidden or inside a private field';
        limitations.add(LegacyWordConversionLimitation.notesComments);
        continue;
      }
      final name = reference.endnote ? 'endnote' : 'footnote';
      _event(owner, reference.anchorCp, 30, () {
        _mediaStart(reference.presentation);
        if (reference.referenceStyle != null) {
          _xml.add('<w:rPr>');
          _runStyle(reference.referenceStyle!);
          _xml.add('</w:rPr>');
        }
        _xml.add(
          '<w:${name}Reference w:id="${reference.id}"${reference.autoNumbered ? '' : ' w:customMarkFollows="1"'}/>',
        );
        _mediaEnd(reference.presentation);
      });
      if (reference.autoNumbered) {
        _event(story.id, story.startCp, 30, () {
          _xml.add('<w:r>');
          if (reference.markerStyle != null) {
            _xml.add('<w:rPr>');
            _runStyle(reference.markerStyle!);
            _xml.add('</w:rPr>');
          }
          _xml.add('<w:${name}Ref/></w:r>');
        });
      }
    }
    _prepareCommentThreads();
    for (final reference in document.commentReferences) {
      if (reference.id < 0 ||
          _stories[reference.storyId]?.kind != LegacyWordStoryKind.comment) {
        throw const FormatException('Invalid Word comment reference.');
      }
      _commentEvidence(reference);
      if (!_displayPosition(reference.anchorCp) ||
          reference.presentation.hidden ||
          _inertStories.containsKey(reference.storyId)) {
        _inertStories[reference.storyId] =
            'comment marker hidden or inside a private field';
        limitations.add(LegacyWordConversionLimitation.notesComments);
        continue;
      }
      final owner = _storyAt(reference.anchorCp);
      if (owner == null) {
        throw const FormatException('Invalid Word comment anchor.');
      }
      if (reference.rangeStartCp != null && reference.rangeEndCp != null) {
        if (reference.rangeStartCp! > reference.rangeEndCp!) {
          throw const FormatException('Invalid Word comment range.');
        }
        _event(
          owner,
          reference.rangeStartCp!,
          20,
          () => _xml.add('<w:commentRangeStart w:id="${reference.id}"/>'),
        );
        _event(
          owner,
          reference.rangeEndCp!,
          reference.rangeStartCp == reference.rangeEndCp ? 21 : 0,
          () => _xml.add('<w:commentRangeEnd w:id="${reference.id}"/>'),
          closing: true,
        );
      }
      _event(owner, reference.anchorCp, 40, () {
        _mediaStart(reference.presentation);
        _xml.add('<w:commentReference w:id="${reference.id}"/>');
        _mediaEnd(reference.presentation);
      });
    }
    for (final field in document.fields) {
      final start = field.storyId == 'main'
          ? 0
          : _stories[field.storyId]?.startCp;
      final end = field.storyId == 'main'
          ? _mainEnd
          : _stories[field.storyId]?.endCp;
      if (_fields.containsKey(field.id) ||
          start == null ||
          end == null ||
          field.startCp < start ||
          field.endCp > end ||
          field.startCp >= field.endCp ||
          (field.separatorCp != null &&
              (field.separatorCp! <= field.startCp ||
                  field.separatorCp! >= field.endCp - 1)) ||
          field.instruction.length !=
              (field.separatorCp ?? field.endCp - 1) - field.startCp - 1) {
        throw const FormatException('Invalid Word field identity or extent.');
      }
      _fields[field.id] = field;
      _displayFieldRevisionEvidence(field);
      if (field.parentId != null) {
        _fieldChildren.putIfAbsent(field.parentId!, () => []).add(field);
      }
    }
    for (final children in _fieldChildren.values) {
      children.sort((a, b) => a.startCp.compareTo(b.startCp));
    }
    // CP ownership determines the immediate parent, even for inactive fields.
    // Checking only that a declared parent contains a child admits crossing
    // roots, overlapping siblings and skipped private ancestors. Input list
    // order is immaterial: the parser normally lists children before parents.
    final orderedFields = document.fields.toList()
      ..sort((a, b) {
        final story = a.storyId.compareTo(b.storyId);
        return story != 0 ? story : a.startCp.compareTo(b.startCp);
      });
    final ancestors = <LegacyWordField>[];
    String? currentStory;
    for (final field in orderedFields) {
      if (field.storyId != currentStory) {
        ancestors.clear();
        currentStory = field.storyId;
      }
      while (ancestors.isNotEmpty && ancestors.last.endCp <= field.startCp) {
        ancestors.removeLast();
      }
      final parent = ancestors.isEmpty ? null : ancestors.last;
      if (field.parentId != parent?.id ||
          parent != null &&
              (parent.startCp >= field.startCp ||
                  parent.endCp <= field.endCp ||
                  (parent.separatorCp != null &&
                      field.startCp <= parent.separatorCp! &&
                      field.endCp > parent.separatorCp!))) {
        throw const FormatException('Invalid Word field nesting.');
      }
      if (ancestors.length >= 64) _tooComplex();
      ancestors.add(field);
    }
    var hiddenInstructionRanges = 0;
    for (final field in document.fields) {
      hiddenInstructionRanges += _validateFieldInstructionVisibility(field);
      if (hiddenInstructionRanges > 200000) _tooComplex();
      if (fieldMode == LegacyWordFieldMode.cachedResults) {
        _cachedFieldEvidence(field);
        continue;
      }
      // Every descendant of an instruction field is emitted while recursively
      // writing that instruction, including fields in its cached result.
      // Private ancestors suppress their entire result subtree. Scheduling
      // these descendants globally leaks hidden instructions or duplicates
      // field markers outside their original containing field.
      if (_fieldHandledByAncestor(field)) continue;
      if (!_safeFieldTree(field)) {
        _inertFieldEvidence(field);
        continue;
      }
      _event(field.storyId, field.startCp, 10, () => _fieldBegin(field));
      if (field.separatorCp != null) {
        _event(
          field.storyId,
          field.separatorCp!,
          10,
          () => _fieldMarker(
            'separate',
            hidden: field.privateResult || field.separatorHidden,
          ),
        );
      }
      _event(
        field.storyId,
        field.endCp - 1,
        5,
        () =>
            _fieldMarker('end', hidden: field.privateResult || field.endHidden),
      );
    }
    _prepareTextboxes();
  }

  int _validateFieldInstructionVisibility(LegacyWordField field) {
    final ranges = field.instructionHiddenRanges;
    if (ranges.length > 200000) _tooComplex();
    final children = _fieldChildren[field.id] ?? const <LegacyWordField>[];
    var previousEnd = 0, childIndex = 0;
    bool splitsScalar(int offset) =>
        offset > 0 &&
        offset < field.instruction.length &&
        field.instruction.codeUnitAt(offset) >= 0xdc00 &&
        field.instruction.codeUnitAt(offset) <= 0xdfff;
    for (final (start, end) in ranges) {
      if (start < previousEnd ||
          start < 0 ||
          end <= start ||
          end > field.instruction.length ||
          splitsScalar(start) ||
          splitsScalar(end)) {
        throw const FormatException(
          'Invalid Word instruction visibility range.',
        );
      }
      final sourceStart = field.startCp + 1 + start;
      final sourceEnd = field.startCp + 1 + end;
      while (childIndex < children.length &&
          children[childIndex].endCp <= sourceStart) {
        childIndex++;
      }
      if (childIndex < children.length &&
          children[childIndex].startCp < sourceEnd) {
        throw const FormatException(
          'Word instruction visibility crosses a nested field.',
        );
      }
      for (var offset = start; offset < end; offset++) {
        final unit = field.instruction.codeUnitAt(offset);
        if (unit == 19 || unit == 20 || unit == 21) {
          throw const FormatException(
            'Word instruction visibility includes a field marker.',
          );
        }
      }
      previousEnd = end;
    }
    return ranges.length;
  }

  bool _fieldHandledByAncestor(LegacyWordField field) {
    var current = field, depth = 0;
    while (current.parentId != null) {
      if (++depth > 64) _tooComplex();
      final parent = _fields[current.parentId]!;
      if (parent.privateResult ||
          current.startCp < (parent.separatorCp ?? parent.endCp - 1)) {
        return true;
      }
      current = parent;
    }
    return false;
  }

  void _inertFieldEvidence(LegacyWordField field) {
    limitations.add(LegacyWordConversionLimitation.fieldsLists);
    _evidenceRecords.add({
      'kind': 'field',
      'type': field.type,
      'instruction': field.instruction,
      'storedResult': field.storedResult,
      'story': field.storyId,
      'startCp': field.startCp,
      'endCp': field.endCp,
      'privateResult': field.privateResult,
      if (field.displayRevision != null)
        'displayRevision':
            _displayFieldRevisionRecords[field.id]!['displayRevision'],
      'reason': 'inert; no external or unsupported field evaluation',
    });
  }

  void _cachedFieldEvidence(LegacyWordField field) {
    if (_evidenceRecords.length >= 20000) _tooComplex();
    limitations.add(LegacyWordConversionLimitation.fieldsLists);
    _evidenceRecords.add({
      'kind': 'cachedField',
      'id': field.id,
      'parentId': field.parentId,
      'type': field.type,
      'instruction': field.instruction,
      'storedResult': field.storedResult,
      'story': field.storyId,
      'startCp': field.startCp,
      'separatorCp': field.separatorCp,
      'endCp': field.endCp,
      'locked': field.locked,
      'dirty': field.dirty,
      'privateResult': field.privateResult,
      'mode': 'cachedResults',
      'beginHidden': field.beginHidden,
      'separatorHidden': field.separatorHidden,
      'endHidden': field.endHidden,
      'instructionHiddenRanges': [
        for (final (start, end) in field.instructionHiddenRanges) [start, end],
      ],
      if (field.displayRevision != null)
        'displayRevision':
            _displayFieldRevisionRecords[field.id]!['displayRevision'],
      'automaticRecalculation': false,
      'reason':
          'Explicit stored-result export; field instructions and nesting are '
          'inert evidence, and the original display runs retain their styling '
          'and source positions. Field editing and recalculation are unavailable.',
    });
    _count('cachedResultFields');
  }

  static final _fieldKeyword = RegExp(r'^\s*([A-Za-z][A-Za-z0-9_]*|=)');

  bool _safeField(LegacyWordField field) {
    final instruction = _fieldInstruction(field);
    final type = field.type.toUpperCase();
    // Public document models may be caller-built. A supplied label must not
    // authorize an unrelated active instruction, including an external field.
    if (_fieldKeyword.firstMatch(instruction)?.group(1)?.toUpperCase() !=
        type) {
      return false;
    }
    if (!const {
      'TOC',
      'REF',
      'PAGEREF',
      'NOTEREF',
      'STYLEREF',
      'PAGE',
      'NUMPAGES',
      'SECTION',
      'SECTIONPAGES',
      'SEQ',
      'LISTNUM',
      'TC',
      'XE',
      'INDEX',
      'HYPERLINK',
      'DATE',
      'TIME',
      'CREATEDATE',
      'SAVEDATE',
      'PRINTDATE',
      'AUTHOR',
      'TITLE',
      'SUBJECT',
      'KEYWORDS',
      'DOCPROPERTY',
      'DOCVARIABLE',
      'QUOTE',
      'IF',
      '=',
    }.contains(type)) {
      return false;
    }
    // A typed child occupies a whole source range in this raw instruction,
    // including its cached result. Word text controls in that result are not
    // instruction text. Validate only the slices emitted as instrText here;
    // _safeFieldTree checks each child's instruction independently.
    final start = field.startCp + 1;
    final end = field.separatorCp ?? field.endCp - 1;
    var position = start;
    bool safeTextUntil(int cp) {
      final value = instruction.substring(position - start, cp - start);
      return value.runes.every(
        (rune) =>
            (rune >= 0x20 && rune != 0xfffe && rune != 0xffff) ||
            const {9, 10, 13}.contains(rune),
      );
    }

    for (final child in _fieldChildren[field.id] ?? const <LegacyWordField>[]) {
      if (child.startCp >= end) break;
      if (child.startCp < position || child.endCp > end) {
        throw const FormatException('Overlapping Word field instructions.');
      }
      if (!safeTextUntil(child.startCp)) return false;
      position = child.endCp;
    }
    return safeTextUntil(end);
  }

  bool _safeFieldTree(LegacyWordField field, [int depth = 0]) {
    if (depth > 64) _tooComplex();
    if (!_safeField(field)) return false;
    final end = field.separatorCp ?? field.endCp - 1;
    return (_fieldChildren[field.id] ?? const <LegacyWordField>[])
        .where((child) => child.startCp < end)
        .every((child) => _safeFieldTree(child, depth + 1));
  }

  void _fieldRunStart(bool hidden) {
    // A field in an instruction never has a visible result in this story.
    // Explicit run visibility prevents importers from exposing nested caches
    // or private-field recalculation errors, while retaining every field and
    // instruction. Preserve source marker/instruction visibility, explicitly
    // resetting visible runs so a previous hidden run cannot leak its style.
    _xml.add('<w:r><w:rPr>');
    _bool('vanish', hidden);
    _xml.add('</w:rPr>');
  }

  void _fieldMarker(String type, {required bool hidden}) {
    _fieldRunStart(hidden);
    _xml.add('<w:fldChar w:fldCharType="$type"/></w:r>');
  }

  void _fieldBegin(
    LegacyWordField field, [
    int depth = 0,
    bool instructionContext = false,
  ]) {
    if (depth > 64) _tooComplex();
    final hidden = instructionContext || field.privateResult;
    final instruction = _fieldInstruction(field);
    if (instruction != field.instruction) {
      final reference = _referenceHyperlinkInstruction(field);
      _count(
        reference == null ? 'binaryHyperlinkFields' : 'binaryReferenceFields',
      );
      _evidenceRecords.add({
        'kind': reference == null
            ? 'binaryHyperlinkField'
            : 'binaryReferenceField',
        'story': field.storyId,
        'startCp': field.startCp,
        'instruction': field.instruction,
        'emittedInstruction': instruction,
        if (reference != null) 'recoveredNativeTerminator': reference.$2,
        'reason':
            'A referenced HFD target agrees with the literal field '
            'target; its binary metadata marker is not instruction text. '
            'The original data is retained and no link is traversed.'
            '${reference?.$2 == true ? ' The reference-only extra zero UTF-16 terminator matches the native producer form.' : ''}',
      });
    }
    _fieldRunStart(hidden || field.beginHidden);
    _xml.add('<w:fldChar w:fldCharType="begin" w:fldLock="1" w:dirty="0">');
    _displayFieldRevision(field);
    _xml.add('</w:fldChar></w:r>');
    final instructionStart = field.startCp + 1;
    final instructionEnd = field.separatorCp ?? field.endCp - 1;
    final children = (_fieldChildren[field.id] ?? const <LegacyWordField>[])
        .where((child) => child.startCp < instructionEnd);
    final visibility = field.instructionHiddenRanges;
    var visibilityIndex = 0;
    var position = instructionStart;
    void textUntil(int cp) {
      final start = position - instructionStart;
      final end = cp - instructionStart;
      if (start < 0 || end < start || end > field.instruction.length) {
        throw const FormatException(
          'Word field instruction positions do not match text.',
        );
      }
      var offset = start;
      while (offset < end) {
        while (visibilityIndex < visibility.length &&
            visibility[visibilityIndex].$2 <= offset) {
          visibilityIndex++;
        }
        final range = visibilityIndex < visibility.length
            ? visibility[visibilityIndex]
            : null;
        final sourceHidden = range != null && range.$1 <= offset;
        final boundary = range == null
            ? end
            : (sourceHidden ? range.$2 : range.$1);
        final limit = boundary < end ? boundary : end;
        final value = instruction.substring(offset, limit);
        _fieldRunStart(hidden || sourceHidden);
        _xml.add('<w:instrText xml:space="preserve">');
        // Whitespace can also occur inside quoted literals; replacing it with
        // spaces changes the retained instruction. XML character references
        // preserve it exactly. Nested field markers use their typed child.
        _xml.text(value, preserveWhitespace: true);
        _xml.add('</w:instrText></w:r>');
        offset = limit;
      }
      position = cp;
    }

    for (final child in children) {
      textUntil(child.startCp);
      if (!_safeField(child)) {
        throw const FormatException(
          'An unsupported nested Word instruction cannot be activated.',
        );
      }
      _fieldBegin(child, depth + 1, true);
      if (child.separatorCp != null) {
        _fieldMarker('separate', hidden: true);
        _writeCachedFieldResult(
          child,
          field.instruction,
          instructionStart,
          depth + 1,
        );
      }
      _fieldMarker('end', hidden: true);
      position = child.endCp;
    }
    textUntil(instructionEnd);
    _count('fields');
  }

  void _writeCachedFieldResult(
    LegacyWordField field,
    String instruction,
    int instructionStart,
    int depth, {
    bool emitFields = true,
  }) {
    if (depth > 64) _tooComplex();
    if (field.privateResult || field.separatorCp == null) return;
    final start = field.separatorCp! + 1;
    final end = field.endCp - 1;
    // storedResult is normalized display text: nested instructions and private
    // results have already been removed, so its offsets are not source CPs.
    // A nested field's complete raw result is instead retained in the enclosing
    // instruction. Slice that exact source, then emit each typed child in place.
    if (start < instructionStart ||
        end < start ||
        end > instructionStart + instruction.length) {
      throw const FormatException(
        'Word field result positions do not match text.',
      );
    }
    var position = start;
    void textUntil(int cp) {
      final output = StringBuffer();
      for (
        var offset = position - instructionStart;
        offset < cp - instructionStart;
        offset++
      ) {
        final unit = instruction.codeUnitAt(offset);
        if (unit == 19 || unit == 20 || unit == 21) {
          throw const FormatException('Unmatched nested Word result field.');
        }
        if (unit == 13 || unit == 11) {
          output.write('\n');
        } else if (unit == 7) {
          output.write('\t');
        } else if (unit == 30) {
          output.writeCharCode(0x2011);
        } else if (unit == 31) {
          output.writeCharCode(0x00ad);
        } else if (unit >= 32 ||
            unit == 9 ||
            unit == 10 ||
            unit == 12 ||
            unit == 14) {
          output.writeCharCode(unit);
        }
      }
      final text = output.toString();
      if (text.isNotEmpty) {
        _writeRun(
          LegacyWordRun(
            startCp: 0,
            endCp: text.length,
            text: text,
            style: const LegacyWordCharacterStyle(hidden: true),
          ),
        );
      }
      position = cp;
    }

    for (final child in _fieldChildren[field.id] ?? const <LegacyWordField>[]) {
      if (child.startCp < start) continue;
      if (child.startCp < position || child.endCp > end) {
        throw const FormatException('Overlapping Word field results.');
      }
      textUntil(child.startCp);
      final active = emitFields && _safeFieldTree(child);
      if (active) {
        _fieldBegin(child, depth + 1, true);
        if (child.separatorCp != null) {
          _fieldMarker('separate', hidden: true);
        }
      } else if (emitFields) {
        _inertFieldEvidence(child);
      }
      _writeCachedFieldResult(
        child,
        instruction,
        instructionStart,
        depth + 1,
        emitFields: active,
      );
      if (active) {
        _fieldMarker('end', hidden: true);
      }
      position = child.endCp;
    }
    textUntil(end);
  }

  void _writeAuxiliaryStories() {
    for (final story in document.stories) {
      final path = _storyParts[story.id];
      if (path == null) continue;
      final header = story.kind == LegacyWordStoryKind.header;
      final root = header ? 'hdr' : 'ftr';
      final xml = _wordPart(root);
      _withStory(story, path, xml, () => _blocks(story.blocks));
      xml.add('</w:$root>');
      _package.addXml(
        path,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.${header ? 'header' : 'footer'}+xml',
        xml,
      );
      _count(header ? 'headers' : 'footers');
    }
    for (final endnote in [false, true]) {
      final refs = document.noteReferences
          .where(
            (reference) =>
                reference.endnote == endnote &&
                !_inertStories.containsKey(reference.storyId),
          )
          .toList();
      if (refs.isEmpty) continue;
      final singular = endnote ? 'endnote' : 'footnote';
      final plural = '${singular}s';
      final path = 'word/$plural.xml';
      final xml = _wordPart(plural);
      final ids = <int>{};
      final separatorKinds = endnote
          ? [
              LegacyWordStoryKind.endnoteSeparator,
              LegacyWordStoryKind.endnoteContinuationSeparator,
              LegacyWordStoryKind.endnoteContinuationNotice,
            ]
          : [
              LegacyWordStoryKind.footnoteSeparator,
              LegacyWordStoryKind.footnoteContinuationSeparator,
              LegacyWordStoryKind.footnoteContinuationNotice,
            ];
      for (var index = 0; index < separatorKinds.length; index++) {
        final matches = document.stories
            .where((story) => story.kind == separatorKinds[index])
            .toList();
        if (matches.length > 1) {
          throw const FormatException('Duplicate Word note separator.');
        }
        if (index == 2 && matches.isEmpty) continue;
        final id = index == 0
            ? -1
            : index == 1
            ? 0
            : -2;
        final type = [
          'separator',
          'continuationSeparator',
          'continuationNotice',
        ][index];
        xml.add('<w:$singular w:type="$type" w:id="$id">');
        if (matches.isNotEmpty) {
          _withStory(
            matches.single,
            path,
            xml,
            () => _blocks(matches.single.blocks, paragraphAfterTable: false),
          );
        } else {
          xml.add('<w:p><w:r><w:$type/></w:r></w:p>');
        }
        xml.add('</w:$singular>');
      }
      for (final reference in refs) {
        if (!ids.add(reference.id)) {
          throw const FormatException('Duplicate Word note identifier.');
        }
        final story = _stories[reference.storyId]!;
        xml.add('<w:$singular w:id="${reference.id}">');
        _withStory(
          story,
          path,
          xml,
          () => _blocks(story.blocks, paragraphAfterTable: false),
        );
        xml.add('</w:$singular>');
        _count(plural);
      }
      xml.add('</w:$plural>');
      _package.addXml(
        path,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.$plural+xml',
        xml,
      );
      _package.relate(
        'word/document.xml',
        '$_relationshipNamespace/$plural',
        '$plural.xml',
      );
    }
    final comments = document.commentReferences.where(
      (reference) => !_inertStories.containsKey(reference.storyId),
    );
    if (comments.isNotEmpty) {
      final xml = _wordPart('comments');
      final ids = <int>{};
      for (final reference in comments) {
        if (!ids.add(reference.id)) {
          throw const FormatException('Duplicate Word comment identifier.');
        }
        xml.add('<w:comment w:id="${reference.id}" w:author="');
        xml.text(reference.author ?? '', attribute: true);
        xml.add('"');
        if (reference.initials != null) {
          xml.add(' w:initials="');
          xml.text(reference.initials!, attribute: true);
          xml.add('"');
        }
        if (reference.time != null) {
          xml.add(' w:date="${_wallClock(reference.time!)}"');
        }
        xml.add('>');
        final story = _stories[reference.storyId]!;
        _withStory(
          story,
          'word/comments.xml',
          xml,
          () => _blocks(story.blocks),
        );
        xml.add('</w:comment>');
        _count('comments');
      }
      xml.add('</w:comments>');
      _package.addXml(
        'word/comments.xml',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml',
        xml,
      );
      _package.relate(
        'word/document.xml',
        '$_relationshipNamespace/comments',
        'comments.xml',
      );
      _writeCommentThreads(comments.toList());
    }
    final settings = _wordPart('settings');
    final defaultTabs = document.defaultTabStopTwips;
    if (defaultTabs != null) {
      if (defaultTabs <= 0 || defaultTabs > 65535) {
        throw const FormatException('Invalid Word default tab interval.');
      }
      settings.add('<w:defaultTabStop w:val="$defaultTabs"/>');
    }
    if (document.evenAndOddHeaders) {
      settings.add('<w:evenAndOddHeaders/>');
    }
    settings.add('<w:updateFields w:val="false"/>');
    _writeCompatibility(settings);
    settings.add('</w:settings>');
    _package.addXml(
      'word/settings.xml',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml',
      settings,
    );
    _package.relate(
      'word/document.xml',
      '$_relationshipNamespace/settings',
      'settings.xml',
    );
  }

  _BoundedWordXml _wordPart(String root) => _BoundedWordXml()
    ..add(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:$root $_wordNamespaces>',
    );

  void _withStory(
    LegacyWordStory story,
    String part,
    _BoundedWordXml xml,
    void Function() action,
  ) {
    if (!_renderingStories.add(story.id) || _renderingStories.length > 32) {
      throw const FormatException('Recursive Word story reference.');
    }
    final oldXml = _xml, oldPart = _part, oldStory = _storyId;
    _xml = xml;
    _part = part;
    _storyId = story.id;
    try {
      action();
      _finishStoryEvents();
    } finally {
      _xml = oldXml;
      _part = oldPart;
      _storyId = oldStory;
      _renderingStories.remove(story.id);
    }
  }

  void _blocks(
    List<LegacyWordBlock> blocks, {
    bool paragraphAfterTable = true,
  }) {
    for (final block in blocks) {
      switch (block) {
        case LegacyWordParagraph():
          _paragraph(block);
        case LegacyWordTable():
          _table(block);
      }
    }
    // CT_FtnEdn permits a table as its final block. A synthesized paragraph
    // changes note height and becomes real content on a subsequent DOC import.
    // Preserve every parsed paragraph; this option changes only the fallback.
    if (blocks.isEmpty ||
        (paragraphAfterTable && blocks.last is LegacyWordTable)) {
      _xml.add('<w:p');
      _commentParagraphAttribute();
      _xml.add('/>');
    }
  }

  void _summarizeLimitations() {
    for (final warning in document.warnings) {
      switch (warning) {
        case LegacyWordWarning.recoveredTableStoryBoundary:
          limitations.add(LegacyWordConversionLimitation.partialFormatting);
        case LegacyWordWarning.unsupportedFormatting:
        case LegacyWordWarning.nestedTablesFlattened:
        case LegacyWordWarning.recoveredNonconformingProperties:
        case LegacyWordWarning.recoveredEmptySection:
        case LegacyWordWarning.recoveredTextboxChainLength:
        case LegacyWordWarning.recoveredSharedHeaderTextbox:
        case LegacyWordWarning.terminalMarkFormattingUnavailable:
        case LegacyWordWarning.recoveredGlobalTextboxSentinel:
        case LegacyWordWarning.recoveredHeaderTextboxAlias:
        case LegacyWordWarning.recoveredHeaderTextboxShapeAlias:
        case LegacyWordWarning.recoveredLegacyDiagonalBorder:
        case LegacyWordWarning.recoveredUnpositionedTextbox:
          limitations.add(LegacyWordConversionLimitation.partialFormatting);
        case LegacyWordWarning.numberingNotReconstructed:
          limitations.add(LegacyWordConversionLimitation.fieldsLists);
        case LegacyWordWarning.fieldsUseStoredResults:
          if (document.fields.isEmpty) {
            limitations.add(LegacyWordConversionLimitation.fieldsLists);
          }
        case LegacyWordWarning.imagesOmitted:
          if (document.media.pictures.isEmpty &&
              document.media.drawings.isEmpty) {
            limitations.add(LegacyWordConversionLimitation.images);
          }
        case LegacyWordWarning.floatingObjectsOmitted:
          if (document.media.drawings.isEmpty &&
              document.media.embeddedObjects.isEmpty) {
            limitations.add(LegacyWordConversionLimitation.embeddedObjects);
          }
        case LegacyWordWarning.textboxesOmitted:
          limitations.add(LegacyWordConversionLimitation.embeddedObjects);
        case LegacyWordWarning.headersFootersOmitted:
          limitations.add(LegacyWordConversionLimitation.headersFooters);
        case LegacyWordWarning.notesOmitted:
        case LegacyWordWarning.unsupportedNoteNumberFormat:
          limitations.add(LegacyWordConversionLimitation.notesComments);
        case LegacyWordWarning.commentsOmitted:
          limitations.add(LegacyWordConversionLimitation.notesComments);
        case LegacyWordWarning.macrosOmitted:
          if ((counts['vbaProjects'] ?? 0) == 0) {
            limitations.add(LegacyWordConversionLimitation.macrosSignatures);
          }
        case LegacyWordWarning.revisionMetadataIncomplete:
          limitations.add(LegacyWordConversionLimitation.revisions);
      }
    }
  }
}

String _wallClock(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-${two(time.day)}T${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
