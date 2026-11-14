// SPDX-License-Identifier: MPL-2.0

part of 'conversion.dart';

extension _WordCommentWriter on _StructuredWordWriter {
  void _prepareCommentThreads() {
    if (document.commentReferences.length > 4096) _tooComplex();
    final stories = <String>{};
    for (final reference in document.commentReferences) {
      if (reference.id < 0 ||
          _commentsById.containsKey(reference.id) ||
          !stories.add(reference.storyId) ||
          _stories[reference.storyId]?.kind != LegacyWordStoryKind.comment) {
        throw const FormatException(
          'Invalid or duplicate Word comment reference.',
        );
      }
      // Visibility never makes an invalid source position acceptable. Validate
      // every thread member before hidden-parent propagation can suppress it.
      final owner = _storyAt(reference.anchorCp);
      if (owner == null) {
        throw const FormatException('Invalid Word comment anchor.');
      }
      final rangeStart = reference.rangeStartCp;
      final rangeEnd = reference.rangeEndCp;
      if ((rangeStart == null) != (rangeEnd == null)) {
        throw const FormatException('Invalid Word comment range.');
      }
      if (rangeStart != null && rangeEnd != null) {
        final start = owner == 'main' ? 0 : _stories[owner]!.startCp;
        final end = owner == 'main' ? _mainEnd : _stories[owner]!.endCp;
        if (rangeStart < start || rangeEnd > end || rangeStart > rangeEnd) {
          throw const FormatException('Invalid Word comment range.');
        }
      }
      _commentsById[reference.id] = reference;
      if (!_displayPosition(reference.anchorCp) ||
          reference.presentation.hidden) {
        _inertStories[reference.storyId] =
            'comment marker hidden or inside a private field';
      }
    }
    final depths = <int, int>{};
    for (final reference in document.commentReferences) {
      var cursor = reference;
      final path = <int>[];
      final active = <int>{};
      while (!depths.containsKey(cursor.id)) {
        if (!active.add(cursor.id) || path.length > 64) {
          throw const FormatException(
            'Cyclic or excessive Word comment thread.',
          );
        }
        path.add(cursor.id);
        final parent = cursor.parentId;
        if (parent == null) break;
        final next = _commentsById[parent];
        if (next == null) {
          throw const FormatException('Missing Word parent comment.');
        }
        cursor = next;
      }
      var depth = depths[cursor.id] ?? -1;
      for (final id in path.reversed) {
        if (++depth > 64) {
          throw const FormatException('Excessive Word comment thread depth.');
        }
        depths[id] = depth;
        final comment = _commentsById[id]!;
        final parent = comment.parentId == null
            ? null
            : _commentsById[comment.parentId];
        if (parent != null && _inertStories.containsKey(parent.storyId)) {
          _inertStories[comment.storyId] =
              'reply to a hidden or private comment';
        }
      }
    }
  }

  void _commentEvidence(LegacyWordCommentReference reference) {
    final source = reference.sourceRecord;
    if (source != null) {
      _preserveEvidence('commentRecord', source.bytes, {
        'commentId': reference.id,
        'sourceStructure': 'ATRDPost10',
        'tableOffset': source.tableOffset,
        'depth': source.depth,
        'relativeParent': source.relativeParent,
        'rawDttm': source.rawDate,
        'ink': reference.ink,
      });
    }
    if (reference.ink) {
      limitations.add(LegacyWordConversionLimitation.notesComments);
      _evidenceRecords.add({
        'kind': 'inkComment',
        'commentId': reference.id,
        'storyId': reference.storyId,
        'reason':
            'ink annotation flag retained; pen-stroke semantics are not reconstructed',
      });
    }
  }

  // Native commentEx joins use the LAST paragraph's ID, not the comment ID.
  // IDs are assigned during actual traversal, including generated empty final
  // paragraphs after tables, so the join remains correct for rich comments.
  void _commentParagraphAttribute() {
    if (_part != 'word/comments.xml' ||
        _stories[_storyId]?.kind != LegacyWordStoryKind.comment) {
      return;
    }
    if (++_commentParagraphSequence > 200000) _tooComplex();
    final id = _commentParagraphSequence
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase();
    _commentParagraphIds[_storyId] = id;
    _xml.add(' w14:paraId="$id"');
  }

  void _writeCommentThreads(List<LegacyWordCommentReference> comments) {
    if (!comments.any((comment) => comment.parentId != null)) return;
    final xml = _BoundedWordXml();
    xml.add(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w15:commentsEx xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml">',
    );
    final active = {for (final comment in comments) comment.id: comment};
    for (final comment in comments) {
      final paragraph = _commentParagraphIds[comment.storyId];
      if (paragraph == null) {
        throw const FormatException('Word comment has no final paragraph.');
      }
      xml.add('<w15:commentEx w15:paraId="$paragraph"');
      final parentId = comment.parentId;
      if (parentId != null) {
        final parent = active[parentId];
        final parentParagraph = parent == null
            ? null
            : _commentParagraphIds[parent.storyId];
        if (parentParagraph == null) {
          throw const FormatException(
            'Word comment thread has no active parent.',
          );
        }
        xml.add(' w15:paraIdParent="$parentParagraph"');
        _count('commentReplies');
      }
      // ATRDPost10 has no resolved/done bit. Omit the optional attribute rather
      // than inventing a binary source state; consumers use its normal default.
      xml.add('/>');
    }
    xml.add('</w15:commentsEx>');
    _package.addXml(
      'word/commentsExtended.xml',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml',
      xml,
    );
    _package.relate(
      'word/document.xml',
      'http://schemas.microsoft.com/office/2011/relationships/commentsExtended',
      'commentsExtended.xml',
    );
  }
}
