// SPDX-License-Identifier: MPL-2.0
import 'legacy_word_structured_model.dart';

/// Shared parser/writer validation for one observed nonconforming header case.
/// MS-DOC's cTxbx and ClientTextbox indices still describe a single frame. The
/// second shape is an occurrence in a different header, never a flowing link.
class WordHeaderTextboxAliases {
  WordHeaderTextboxAliases({
    required Iterable<LegacyWordStory> stories,
    required LegacyWordMediaCatalog media,
    required Iterable<LegacyWordField> fields,
    required Iterable<LegacyWordBookmark> bookmarks,
    required Iterable<LegacyWordNoteReference> notes,
    required Iterable<LegacyWordCommentReference> comments,
  }) {
    for (final story in stories) {
      if (_stories.containsKey(story.id)) {
        _invalid = true;
      }
      _stories[story.id] = story;
      _ranges.add(story);
      if (story.kind == LegacyWordStoryKind.headerTextbox &&
          _plainParagraphs(story)) {
        _plainTextboxes.add(story.id);
      }
    }
    _ranges.sort((a, b) => a.startCp.compareTo(b.startCp));
    var end = -1;
    for (final story in _ranges) {
      if (story.startCp < end || story.endCp < story.startCp) {
        _invalid = true;
      }
      end = story.endCp;
    }
    for (final drawing in media.drawings) {
      final key = (drawing.headerStory, drawing.shapeId, drawing.anchorCp);
      if (_drawings.containsKey(key)) _invalid = true;
      _drawings[key] = drawing;
      _shapeCounts.update(
        (drawing.headerStory, drawing.shapeId),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      final id = (drawing.textboxId ?? 0) >> 16;
      if (id > 0) {
        final reference = (drawing.headerStory, id);
        _referenceCounts.update(
          reference,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    // These events have identity or state that cannot safely be replayed as
    // independent header content. Inclusive endpoints also exclude boundary
    // bookmark/field events. Merge once so many aliases do not rescan lists.
    final unsafe = <(int, int)>[
      for (final field in fields) (field.startCp, field.endCp),
      for (final bookmark in bookmarks) (bookmark.startCp, bookmark.endCp),
      for (final note in notes) (note.anchorCp, note.anchorCp),
      for (final comment in comments) ...[
        (comment.anchorCp, comment.anchorCp),
        if (comment.rangeStartCp != null && comment.rangeEndCp != null)
          (comment.rangeStartCp!, comment.rangeEndCp!),
      ],
      for (final picture in media.pictures) (picture.cp, picture.cp),
      for (final object in media.embeddedObjects) (object.cp, object.cp),
      for (final drawing in media.drawings)
        (drawing.anchorCp, drawing.anchorCp),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final interval in unsafe) {
      if (interval.$2 < interval.$1) _invalid = true;
      if (_unsafe.isNotEmpty && interval.$1 <= _unsafe.last.$2) {
        final prior = _unsafe.removeLast();
        _unsafe.add((
          prior.$1,
          prior.$2 > interval.$2 ? prior.$2 : interval.$2,
        ));
      } else {
        _unsafe.add(interval);
      }
    }
    for (final field in fields) {
      _plainTextboxes.remove(field.storyId);
    }
  }

  final _stories = <String, LegacyWordStory>{};
  final _ranges = <LegacyWordStory>[];
  final _drawings = <(bool, int, int), LegacyWordDrawing>{};
  final _shapeCounts = <(bool, int), int>{};
  final _referenceCounts = <(bool, int), int>{};
  final _plainTextboxes = <String>{};
  final _unsafe = <(int, int)>[];
  var _invalid = false;

  WordHeaderTextboxAliasPair? resolve(
    LegacyWordTextboxReference reference,
    List<LegacyWordTextboxAnchor> occurrences,
  ) {
    final text = _stories[reference.storyId];
    if (_invalid ||
        !reference.inHeaderFooter ||
        reference.id < 1 ||
        reference.id > 0xffff ||
        reference.chainLength != 1 ||
        reference.declaredChainLength != null ||
        reference.nextTextboxId != null ||
        _referenceCounts[(true, reference.id)] != 2 ||
        occurrences.length != 2 ||
        text == null ||
        !_plainTextboxes.contains(text.id) ||
        _hasUnsafeEvent(text.startCp, text.endCp)) {
      return null;
    }
    final first = occurrences[0], second = occurrences[1];
    if (first.anchorCp == second.anchorCp) {
      return null;
    }
    final primary =
        first.shapeId == reference.shapeId &&
            first.anchorCp == reference.anchorCp
        ? first
        : second;
    final alias = identical(primary, first) ? second : first;
    if (primary.shapeId != reference.shapeId ||
        primary.anchorCp != reference.anchorCp) {
      return null;
    }
    for (final occurrence in occurrences) {
      final drawing =
          _drawings[(true, occurrence.shapeId, occurrence.anchorCp)];
      final shape = drawing?.shape;
      if (occurrence.chainIndex != 0 ||
          (occurrence.nextShapeId ?? 0) != 0 ||
          drawing == null ||
          drawing.anchorCp != occurrence.anchorCp ||
          drawing.textboxId != reference.id << 16 ||
          (drawing.nextTextboxShapeId ?? 0) != 0 ||
          drawing.shapeDeleted ||
          drawing.presentation.hidden ||
          drawing.presentation.inserted ||
          drawing.presentation.deleted ||
          drawing.presentation.insertionRevision != null ||
          drawing.presentation.deletionRevision != null ||
          _shapeCounts[(true, occurrence.shapeId)] !=
              (first.shapeId == second.shapeId ? 2 : 1) ||
          shape == null ||
          shape.type != 202 ||
          (shape.sourceFlags & 0x3f) != 0) {
        return null;
      }
    }
    if (first.shapeId == second.shapeId) {
      final a = _drawings[(true, first.shapeId, first.anchorCp)]!;
      final b = _drawings[(true, second.shapeId, second.anchorCp)]!;
      // A native DOC export can retain two distinct header SPA occurrences
      // of one OfficeArt FSP. They must share the actual decoded payload;
      // equal numeric IDs never authorize conflicting shapes or images.
      if (!identical(a.shape, b.shape) ||
          a.officeArtArtifactId != b.officeArtArtifactId ||
          a.imageId != null ||
          b.imageId != null) {
        return null;
      }
    }
    final primaryOwner = _ownerAt(primary.anchorCp);
    final aliasOwner = _ownerAt(alias.anchorCp);
    if (primaryOwner == null ||
        aliasOwner == null ||
        primaryOwner.id == aliasOwner.id ||
        primaryOwner.kind != LegacyWordStoryKind.header ||
        aliasOwner.kind != LegacyWordStoryKind.header ||
        primaryOwner.sectionIndex == null ||
        primaryOwner.sectionIndex! < 0 ||
        primaryOwner.sectionIndex != aliasOwner.sectionIndex ||
        {primaryOwner.headerFooterType, aliasOwner.headerFooterType}.length !=
            2 ||
        ![primaryOwner, aliasOwner].every(
          (story) =>
              story.headerFooterType == LegacyWordHeaderFooterType.normal ||
              story.headerFooterType == LegacyWordHeaderFooterType.first,
        )) {
      return null;
    }
    return WordHeaderTextboxAliasPair(primary, alias, primaryOwner, aliasOwner);
  }

  LegacyWordStory? _ownerAt(int cp) {
    var low = 0, high = _ranges.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final story = _ranges[middle];
      if (cp < story.startCp) {
        high = middle;
      } else if (cp >= story.endCp) {
        low = middle + 1;
      } else {
        return story;
      }
    }
    return null;
  }

  bool _hasUnsafeEvent(int first, int last) {
    var low = 0, high = _unsafe.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final range = _unsafe[middle];
      if (last < range.$1) {
        high = middle;
      } else if (first > range.$2) {
        low = middle + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  static bool _plainParagraphs(LegacyWordStory story) =>
      story.blocks.isNotEmpty &&
      story.blocks.every(
        (block) =>
            block is LegacyWordParagraph &&
            block.style.listId == null &&
            block.numberingRevision == null &&
            block.formattingRevision == null &&
            !(block.mark?.inserted ?? false) &&
            !(block.mark?.deleted ?? false) &&
            block.mark?.insertionRevision == null &&
            block.mark?.deletionRevision == null &&
            block.mark?.formattingRevision == null &&
            block.runs.every(
              (run) =>
                  !run.inserted &&
                  !run.deleted &&
                  run.insertionRevision == null &&
                  run.deletionRevision == null &&
                  run.formattingRevision == null,
            ),
      );
}

class WordHeaderTextboxAliasPair {
  const WordHeaderTextboxAliasPair(
    this.primary,
    this.alias,
    this.primaryOwner,
    this.aliasOwner,
  );
  final LegacyWordTextboxAnchor primary, alias;
  final LegacyWordStory primaryOwner, aliasOwner;
  bool get sharedShape => primary.shapeId == alias.shapeId;
}
