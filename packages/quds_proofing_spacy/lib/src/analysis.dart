import 'dart:convert';

import 'backend.dart';
import 'source_text.dart';

enum LinguisticAnalysisStatus {
  success,
  unavailable,
  unsupported,
  failed,
  cancelled,
  capacity,
  stale,
  timeout,
}

/// A single original-text unit, never an implicitly concatenated document.
final class LinguisticAnalysisRequest {
  LinguisticAnalysisRequest({
    required this.text,
    required this.documentId,
    required this.blockId,
    required this.revision,
    this.locale = 'de-DE',
    this.startOffset = 0,
    this.generation = 0,
    this.configurationId = '',
  }) {
    if (documentId.isEmpty ||
        blockId.isEmpty ||
        documentId.length > 4096 ||
        blockId.length > 4096 ||
        configurationId.length > 4096 ||
        locale.length > 128 ||
        revision < 0 ||
        generation < 0 ||
        startOffset < 0 ||
        startOffset > 0x1fffffffffffff - text.length) {
      throw ArgumentError('Invalid linguistic analysis snapshot identity.');
    }
  }
  final String text;
  final String documentId;
  final String blockId;
  final int revision;
  final String locale;
  final int startOffset;
  final int generation;
  final String configurationId;

  /// Revision/generation are excluded so edits supersede earlier work for the
  /// same unit. JSON framing avoids ambiguous delimiter-based key collisions.
  String get key => jsonEncode([documentId, blockId, startOffset]);

  bool sameSnapshot(LinguisticAnalysisRequest other) =>
      documentId == other.documentId &&
      blockId == other.blockId &&
      revision == other.revision &&
      locale == other.locale &&
      startOffset == other.startOffset &&
      generation == other.generation &&
      configurationId == other.configurationId &&
      text == other.text;
}

/// The available selected contextual reading. These are not calibrated
/// probabilities, alternative parses, inflection paradigms or grammar edits.
final class LinguisticToken {
  const LinguisticToken({
    required this.index,
    required this.text,
    required this.byteStart,
    required this.byteEnd,
    required this.scalarStart,
    required this.scalarEnd,
    required this.start,
    required this.end,
    required this.lemma,
    required this.tag,
    required this.pos,
    required this.morphology,
    required this.dependency,
    required this.head,
    required this.sentenceStart,
    required this.sentenceEnd,
    this.norm = '',
    this.prefix = '',
    this.suffix = '',
    this.shape = '',
    this.spaceAfter = false,
    this.isSpace = false,
  });
  final int index;
  final String text;
  final int byteStart;
  final int byteEnd;
  final int scalarStart;
  final int scalarEnd;

  /// Half-open UTF-16 offsets relative to request.text; add startOffset once.
  final int start;
  final int end;
  final String norm;
  final String prefix;
  final String suffix;
  final String shape;
  final String lemma;
  final String tag;
  final String pos;
  final String morphology;
  final String dependency;

  /// Absolute token index within this analysis unit. Roots point to themselves.
  final int head;
  final bool spaceAfter;
  final bool isSpace;
  final bool sentenceStart;
  final bool sentenceEnd;

  Map<String, Object> toJson() => {
    'i': index,
    'text': text,
    'start_byte': byteStart,
    'end_byte': byteEnd,
    'start_codepoint': scalarStart,
    'end_codepoint': scalarEnd,
    'start_utf16': start,
    'end_utf16': end,
    'norm': norm,
    'prefix': prefix,
    'suffix': suffix,
    'shape': shape,
    'lemma': lemma,
    'tag': tag,
    'pos': pos,
    'morph': morphology,
    'dep': dependency,
    'head': head,
    'whitespace': spaceAfter ? ' ' : '',
    'is_space': isSpace,
    'is_sent_start': sentenceStart,
  };
}

final class LinguisticSentence {
  const LinguisticSentence({
    required this.startToken,
    required this.endToken,
    required this.start,
    required this.end,
    required this.byteStart,
    required this.byteEnd,
    required this.scalarStart,
    required this.scalarEnd,
    required this.text,
  });
  final int startToken;
  final int endToken;
  final int start;
  final int end;
  final int byteStart;
  final int byteEnd;
  final int scalarStart;
  final int scalarEnd;
  final String text;
  Map<String, Object> toJson() => {
    'start_token': startToken,
    'end_token': endToken,
    'start_byte': byteStart,
    'end_byte': byteEnd,
    'start_codepoint': scalarStart,
    'end_codepoint': scalarEnd,
    'start_utf16': start,
    'end_utf16': end,
    'text': text,
  };
}

/// An optional named-entity span covering whole tokens of one analysis unit.
///
/// Entities are reported only when the loaded native runtime provides an
/// entity recognizer; Dart never infers them. Offsets follow the token
/// convention: half-open UTF-16 offsets relative to the request text.
final class LinguisticEntity {
  const LinguisticEntity({
    required this.startToken,
    required this.endToken,
    required this.start,
    required this.end,
    required this.label,
    required this.text,
  });

  /// Half-open token range.
  final int startToken;
  final int endToken;
  final int start;
  final int end;
  final String label;
  final String text;

  Map<String, Object> toJson() => {
    'start_token': startToken,
    'end_token': endToken,
    'start_utf16': start,
    'end_utf16': end,
    'label': label,
    'text': text,
  };
}

final class LinguisticAnalysisResult {
  LinguisticAnalysisResult._(
    this.request,
    this.status,
    this.message,
    this.identity,
    this.tokens,
    this.sentences, {
    this.entities = const [],
    this.entitiesAvailable = false,
  });

  /// [entities] is null when the runtime has no entity recognizer, which is
  /// distinct from an empty list (recognizer ran and found nothing).
  factory LinguisticAnalysisResult.success({
    required LinguisticAnalysisRequest request,
    required SpacyBackendIdentity identity,
    required Iterable<LinguisticToken> tokens,
    Iterable<LinguisticEntity>? entities,
  }) {
    identity.validate();
    if (request.locale != 'de-DE') {
      throw const FormatException('Only de-DE analysis is declared.');
    }
    final owned = List<LinguisticToken>.unmodifiable(tokens);
    final sentences = _validateAnalysis(request, owned);
    final ownedEntities = entities == null
        ? const <LinguisticEntity>[]
        : List<LinguisticEntity>.unmodifiable(entities);
    if (entities != null) _validateEntities(request, owned, ownedEntities);
    return LinguisticAnalysisResult._(
      request,
      LinguisticAnalysisStatus.success,
      null,
      identity,
      owned,
      List.unmodifiable(sentences),
      entities: ownedEntities,
      entitiesAvailable: entities != null,
    );
  }

  factory LinguisticAnalysisResult.failure({
    required LinguisticAnalysisRequest request,
    required LinguisticAnalysisStatus status,
    required String message,
    SpacyBackendIdentity? identity,
  }) {
    if (status == LinguisticAnalysisStatus.success || message.isEmpty) {
      throw ArgumentError('Failure requires an explicit non-success status.');
    }
    return LinguisticAnalysisResult._(
      request,
      status,
      message,
      identity,
      const [],
      const [],
    );
  }

  final LinguisticAnalysisRequest request;
  final LinguisticAnalysisStatus status;
  final String? message;
  final SpacyBackendIdentity? identity;
  final List<LinguisticToken> tokens;
  final List<LinguisticSentence> sentences;

  /// Optional named entities; empty when unavailable or none were found.
  final List<LinguisticEntity> entities;

  /// Whether the runtime reported entity recognition for this result.
  final bool entitiesAvailable;
  bool get isSuccess => status == LinguisticAnalysisStatus.success;
  static const capabilities = <String>{
    'tokens',
    'tags',
    'pos',
    'morphology',
    'lemmas',
    'dependencies',
    'sentences',
  };
  Map<String, Object?> toJson() => {
    'status': status.name,
    'message': message,
    'identity': identity?.toJson(),
    'tokens': tokens.map((token) => token.toJson()).toList(),
    'sentences': sentences.map((sentence) => sentence.toJson()).toList(),
    if (entitiesAvailable)
      'entities': entities.map((entity) => entity.toJson()).toList(),
  };
}

void _validateEntities(
  LinguisticAnalysisRequest request,
  List<LinguisticToken> tokens,
  List<LinguisticEntity> entities,
) {
  var previousEnd = 0;
  for (final entity in entities) {
    if (entity.startToken < previousEnd ||
        entity.endToken <= entity.startToken ||
        entity.endToken > tokens.length ||
        entity.label.isEmpty ||
        entity.label.length > 64 ||
        entity.start != tokens[entity.startToken].start ||
        entity.end != tokens[entity.endToken - 1].end ||
        request.text.substring(entity.start, entity.end) != entity.text) {
      throw const FormatException('Invalid native entity span.');
    }
    previousEnd = entity.endToken;
  }
}

List<LinguisticSentence> _validateAnalysis(
  LinguisticAnalysisRequest request,
  List<LinguisticToken> tokens,
) {
  final source = SpacySourceText(request.text);
  if (tokens.length > spacyMaximumTokens ||
      (source.bytes.isEmpty != tokens.isEmpty)) {
    throw const FormatException('Missing or excessive native tokens.');
  }
  var nextByte = 0;
  var sentenceBegin = 0;
  final sentences = <LinguisticSentence>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.index != i ||
        token.byteStart != nextByte ||
        token.byteEnd <= token.byteStart ||
        token.byteEnd > source.bytes.length ||
        source.utf16At(token.byteStart) != token.start ||
        source.utf16At(token.byteEnd) != token.end ||
        source.scalarAt(token.byteStart) != token.scalarStart ||
        source.scalarAt(token.byteEnd) != token.scalarEnd ||
        request.text.substring(token.start, token.end) != token.text ||
        token.head < 0 ||
        token.head >= tokens.length ||
        token.tag.isEmpty ||
        token.pos.isEmpty ||
        token.dependency.isEmpty ||
        token.sentenceStart != (i == sentenceBegin)) {
      throw const FormatException('Invalid native token annotation or span.');
    }
    nextByte = token.byteEnd;
    if (token.spaceAfter) {
      if (nextByte >= source.bytes.length || source.bytes[nextByte] != 0x20) {
        throw const FormatException('Invalid native trailing whitespace.');
      }
      nextByte++;
    }
    if (token.sentenceEnd) {
      final first = tokens[sentenceBegin];
      var roots = 0;
      for (var j = sentenceBegin; j <= i; j++) {
        final node = tokens[j];
        // The source assigns `dep` to a standalone whitespace root. Root
        // identity is the self-head index, not an invented label restriction.
        if (node.head < sentenceBegin || node.head > i) {
          throw const FormatException('Invalid dependency sentence/head.');
        }
        if (node.head == j) roots++;
      }
      if (roots != 1) {
        throw const FormatException('Sentence must have one dependency root.');
      }
      // Each node must reach the one root; finite bounded walk detects cycles.
      for (var j = sentenceBegin; j <= i; j++) {
        var at = j;
        var steps = 0;
        while (tokens[at].head != at) {
          at = tokens[at].head;
          if (++steps > i - sentenceBegin) {
            throw const FormatException('Cyclic native dependency graph.');
          }
        }
      }
      sentences.add(
        LinguisticSentence(
          startToken: sentenceBegin,
          endToken: i + 1,
          start: first.start,
          end: token.end,
          byteStart: first.byteStart,
          byteEnd: token.byteEnd,
          scalarStart: first.scalarStart,
          scalarEnd: token.scalarEnd,
          text: request.text.substring(first.start, token.end),
        ),
      );
      sentenceBegin = i + 1;
    }
  }
  if (nextByte != source.bytes.length || sentenceBegin != tokens.length) {
    throw const FormatException(
      'Incomplete native source or sentence coverage.',
    );
  }
  return sentences;
}
