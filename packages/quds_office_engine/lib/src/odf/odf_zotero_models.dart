import '../word/model/word_zotero.dart';
import 'odf_zotero_preferences.dart';

/// Native ODT storage, before any conversion into editable Word fields.
enum OdfZoteroStorage { referenceMark, pointMark, section }

/// Physically distinct ODF stories. Unsupported stories remain inventoried.
enum OdfZoteroStory {
  body,
  footnote,
  endnote,
  annotation,
  textBox,
  header,
  footer,
  revision,
  unknown,
}

/// Reasons an identified field is not yet a safe rich-import candidate.
enum OdfZoteroIssueCode {
  legacyName,
  malformedName,
  unsupportedCode,
  invalidMetadata,
  missingStart,
  missingEnd,
  duplicateStart,
  duplicateEnd,
  duplicateName,
  pointMark,
  reversedRange,
  crossStory,
  crossOwner,
  outsideParagraph,
  unsupportedStory,
  unsupportedContent,
  repeatedContent,
  citationAcrossParagraphs,
  nestedRange,
  crossedRange,
  overlappingFields,
  nestedSection,
  protectedSection,
  linkedSection,
  sectionKind,
  emptySection,
  unsupportedSectionStructure,
}

/// Immutable structural ancestor; paths use zero-based element-child indexes.
final class OdfZoteroOwner {
  const OdfZoteroOwner({
    required this.path,
    required this.namespaceUri,
    required this.localName,
  });

  final String path;
  final String namespaceUri;
  final String localName;

  Map<String, Object?> toJson() => {
    'path': path,
    'namespaceUri': namespaceUri,
    'localName': localName,
  };
}

/// An exact endpoint or observation in a selected source XML part.
///
/// [offset] is a UTF-16 code-unit offset into [paragraphPath]'s decoded text.
/// A block boundary outside a paragraph has a null paragraph and offset.
/// [storyPath] separates individual notes, comments and drawing stories.
final class OdfZoteroLocation {
  OdfZoteroLocation({
    required this.part,
    required this.path,
    required this.story,
    required this.storyPath,
    required List<OdfZoteroOwner> owners,
    this.paragraphPath,
    this.paragraphIndex,
    this.offset,
  }) : owners = List.unmodifiable(owners);

  final String part;
  final String path;
  final OdfZoteroStory story;
  final String storyPath;
  final List<OdfZoteroOwner> owners;
  final String? paragraphPath;
  final int? paragraphIndex;
  final int? offset;

  Map<String, Object?> toJson() => {
    'part': part,
    'path': path,
    'story': story.name,
    'storyPath': storyPath,
    'owners': [for (final owner in owners) owner.toJson()],
    'paragraphPath': paragraphPath,
    'paragraphIndex': paragraphIndex,
    'offset': offset,
  };
}

/// A detected ambiguity or unsupported structure; never a silent omission.
final class OdfZoteroIssue {
  const OdfZoteroIssue(this.code, this.message, {this.location});

  final OdfZoteroIssueCode code;
  final String message;
  final OdfZoteroLocation? location;

  Map<String, Object?> toJson() => {
    'code': code.name,
    'message': message,
    if (location != null) 'location': location!.toJson(),
  };
}

/// One decoded paragraph segment owned by an inventoried field.
final class OdfZoteroTextRange {
  const OdfZoteroTextRange({
    required this.location,
    required this.start,
    required this.end,
    required this.text,
  });

  final OdfZoteroLocation location;
  final int start;
  final int end;
  final String text;

  Map<String, Object?> toJson() => {
    'location': location.toJson(),
    'start': start,
    'end': end,
    'text': text,
  };
}

/// Read-only native field evidence, not an active [WmlZoteroField].
final class OdfZoteroField {
  OdfZoteroField({
    required this.name,
    required this.storage,
    required this.logicalCode,
    required this.randomSuffix,
    required this.kind,
    required this.metadata,
    required this.isValid,
    required List<OdfZoteroLocation> starts,
    required List<OdfZoteroLocation> ends,
    required List<OdfZoteroTextRange> ranges,
    required List<OdfZoteroIssue> issues,
  }) : starts = List.unmodifiable(starts),
       ends = List.unmodifiable(ends),
       ranges = List.unmodifiable(ranges),
       issues = List.unmodifiable(issues);

  final String name;
  final OdfZoteroStorage storage;
  final String? logicalCode;
  final String? randomSuffix;
  final ZoteroFieldKind? kind;

  /// Deep immutable metadata from the existing bounded Zotero codec.
  final Map<String, Object?>? metadata;

  /// Name and metadata validity, independent of physical import eligibility.
  final bool isValid;
  final List<OdfZoteroLocation> starts;
  final List<OdfZoteroLocation> ends;
  final List<OdfZoteroTextRange> ranges;
  final List<OdfZoteroIssue> issues;

  /// Candidate for a future rich importer. This reader never enables editing.
  bool get isImportCandidate => isValid && issues.isEmpty;

  /// Paragraph boundaries remain separately available in [ranges].
  String get cachedText => ranges.map((range) => range.text).join('\n');

  Map<String, Object?> toJson() => {
    'name': name,
    'storage': storage.name,
    'logicalCode': logicalCode,
    'randomSuffix': randomSuffix,
    'kind': kind?.name,
    'metadata': metadata,
    'isValid': isValid,
    'isImportCandidate': isImportCandidate,
    'starts': [for (final endpoint in starts) endpoint.toJson()],
    'ends': [for (final endpoint in ends) endpoint.toJson()],
    'ranges': [for (final range in ranges) range.toJson()],
    'cachedText': cachedText,
    'issues': [for (final issue in issues) issue.toJson()],
  };
}

/// A complete bounded inspection. Resource failures throw instead of truncating.
final class OdfZoteroInventory {
  OdfZoteroInventory({
    required List<OdfZoteroField> fields,
    required this.preferences,
    required List<OdfZoteroIssue> issues,
    required this.paragraphCount,
  }) : fields = List.unmodifiable(fields),
       issues = List.unmodifiable(issues);

  final List<OdfZoteroField> fields;
  final OdfZoteroPreferences preferences;

  /// Document-level observations, including objects outside citation ranges.
  final List<OdfZoteroIssue> issues;
  final int paragraphCount;

  Map<String, Object?> toJson() => {
    'format': 'odt',
    'editable': false,
    'paragraphCount': paragraphCount,
    'fields': [for (final field in fields) field.toJson()],
    'preferences': preferences.toJson(),
    'issues': [for (final issue in issues) issue.toJson()],
  };
}

/// Resource ceilings for an inspection, checked before expanding XML content.
final class OdfZoteroLimits {
  const OdfZoteroLimits({
    this.maxArchiveBytes = 64 * 1024 * 1024,
    this.maxZipEntries = 10000,
    this.maxPartBytes = 16 * 1024 * 1024,
    this.maxTotalXmlBytes = 24 * 1024 * 1024,
    this.maxXmlDepth = 128,
    this.maxXmlElements = 200000,
    this.maxFields = 10000,
    this.maxParagraphs = 100000,
    this.maxRangeWork = 200000,
    this.maxFieldRanges = 100000,
    this.maxNameLength = 1024 * 1024 + 32,
    this.maxTextBytes = 16 * 1024 * 1024,
  });

  final int maxArchiveBytes;
  final int maxZipEntries;
  final int maxPartBytes;
  final int maxTotalXmlBytes;
  final int maxXmlDepth;
  final int maxXmlElements;
  final int maxFields;
  final int maxParagraphs;

  /// Candidate paragraph visits accumulated across every field's range scan.
  final int maxRangeWork;

  /// Range records, independently of their possibly empty text content.
  final int maxFieldRanges;
  final int maxNameLength;
  final int maxTextBytes;

  void validate() {
    final values = {
      'maxArchiveBytes': maxArchiveBytes,
      'maxZipEntries': maxZipEntries,
      'maxPartBytes': maxPartBytes,
      'maxTotalXmlBytes': maxTotalXmlBytes,
      'maxXmlDepth': maxXmlDepth,
      'maxXmlElements': maxXmlElements,
      'maxFields': maxFields,
      'maxParagraphs': maxParagraphs,
      'maxRangeWork': maxRangeWork,
      'maxFieldRanges': maxFieldRanges,
      'maxNameLength': maxNameLength,
      'maxTextBytes': maxTextBytes,
    };
    for (final entry in values.entries) {
      if (entry.value < 1) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be positive.');
      }
    }
  }
}

/// The entire inventory failed a resource bound; no partial success is returned.
final class OdfZoteroLimitException extends FormatException {
  const OdfZoteroLimitException(this.limit)
    : super('ODT Zotero inventory exceeds the $limit limit.');

  final String limit;
}
