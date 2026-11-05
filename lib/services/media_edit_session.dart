import 'package:flutter/foundation.dart' show ChangeNotifier, immutable;

enum MediaKind { audio, video }

/// Metadata from the decoder, not a filename or a cached directory listing.
@immutable
class MediaInfo {
  const MediaInfo({
    required this.kind,
    required this.duration,
    this.width,
    this.height,
    this.sampleRate,
    this.channels,
    this.frameRate,
  });

  final MediaKind kind;
  final Duration duration;
  final int? width;
  final int? height;
  final int? sampleRate;
  final int? channels;
  final double? frameRate;
}

/// Normalized crop in the source's display orientation, before user rotation.
@immutable
class MediaCrop {
  const MediaCrop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  bool get isValid =>
      x.isFinite &&
      y.isFinite &&
      width.isFinite &&
      height.isFinite &&
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1.000000001 &&
      y + height <= 1.000000001;

  @override
  bool operator ==(Object other) =>
      other is MediaCrop &&
      x == other.x &&
      y == other.y &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// A nondestructive edit. Times refer to the immutable staged source; fades
/// are relative to the selected output segment, never to the untrimmed file.
@immutable
class MediaEdit {
  const MediaEdit({
    required this.start,
    required this.end,
    this.gainDb = 0,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.muted = false,
    this.quarterTurns = 0,
    this.crop,
    this.maxOutputHeight,
  });

  final Duration start;
  final Duration end;
  final double gainDb;
  final Duration fadeIn;
  final Duration fadeOut;
  final bool muted;
  final int quarterTurns;
  final MediaCrop? crop;
  final int? maxOutputHeight;

  Duration get duration => end - start;

  MediaEdit copyWith({
    Duration? start,
    Duration? end,
    double? gainDb,
    Duration? fadeIn,
    Duration? fadeOut,
    bool? muted,
    int? quarterTurns,
    MediaCrop? crop,
    bool clearCrop = false,
    int? maxOutputHeight,
    bool clearMaxOutputHeight = false,
  }) => MediaEdit(
    start: start ?? this.start,
    end: end ?? this.end,
    gainDb: gainDb ?? this.gainDb,
    fadeIn: fadeIn ?? this.fadeIn,
    fadeOut: fadeOut ?? this.fadeOut,
    muted: muted ?? this.muted,
    quarterTurns: quarterTurns ?? this.quarterTurns,
    crop: clearCrop ? null : (crop ?? this.crop),
    maxOutputHeight: clearMaxOutputHeight
        ? null
        : (maxOutputHeight ?? this.maxOutputHeight),
  );

  void validate(MediaInfo info) {
    if (info.duration <= Duration.zero ||
        start < Duration.zero ||
        end <= start ||
        end > info.duration ||
        !gainDb.isFinite ||
        gainDb < -60 ||
        gainDb > 12 ||
        fadeIn < Duration.zero ||
        fadeOut < Duration.zero ||
        fadeIn > duration ||
        fadeOut > duration ||
        quarterTurns < 0 ||
        quarterTurns > 3 ||
        (crop != null && !crop!.isValid) ||
        (maxOutputHeight != null &&
            (maxOutputHeight! < 2 || maxOutputHeight! > 4320))) {
      throw const MediaEditException(MediaEditFailure.invalidEdit);
    }
    if (info.kind == MediaKind.audio &&
        (quarterTurns != 0 || crop != null || maxOutputHeight != null)) {
      throw const MediaEditException(MediaEditFailure.unsupportedEdit);
    }
    // Video gain/fades need explicit engine parity before the host exposes them.
    if (info.kind == MediaKind.video &&
        (gainDb != 0 || fadeIn != Duration.zero || fadeOut != Duration.zero)) {
      throw const MediaEditException(MediaEditFailure.unsupportedEdit);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MediaEdit &&
      start == other.start &&
      end == other.end &&
      gainDb == other.gainDb &&
      fadeIn == other.fadeIn &&
      fadeOut == other.fadeOut &&
      muted == other.muted &&
      quarterTurns == other.quarterTurns &&
      crop == other.crop &&
      maxOutputHeight == other.maxOutputHeight;

  @override
  int get hashCode => Object.hash(
    start,
    end,
    gainDb,
    fadeIn,
    fadeOut,
    muted,
    quarterTurns,
    crop,
    maxOutputHeight,
  );
}

enum MediaEditFailure { invalidMedia, invalidEdit, unsupportedEdit, busy }

class MediaEditException implements Exception {
  const MediaEditException(this.reason);
  final MediaEditFailure reason;
  @override
  String toString() => 'MediaEditException(${reason.name})';
}

@immutable
class MediaEditRevision {
  const MediaEditRevision(this.id, this.edit);
  final int id;
  final MediaEdit edit;
}

/// History stores small recipes, never decoded media buffers. A saved revision
/// has a unique identity so branching after undo cannot reuse a clean index.
class MediaEditSession extends ChangeNotifier {
  MediaEditSession(this.info) {
    if (info.duration <= Duration.zero ||
        (info.kind == MediaKind.video &&
            ((info.width ?? 0) < 2 || (info.height ?? 0) < 2))) {
      throw const MediaEditException(MediaEditFailure.invalidMedia);
    }
    _history.add(
      MediaEditRevision(0, MediaEdit(start: Duration.zero, end: info.duration)),
    );
  }

  final MediaInfo info;
  final List<MediaEditRevision> _history = [];
  int _index = 0;
  int _nextId = 1;
  int _savedId = 0;
  MediaEditRevision? _exporting;

  MediaEditRevision get revision => _history[_index];
  MediaEdit get edit => revision.edit;
  bool get isDirty => revision.id != _savedId;
  bool get isExporting => _exporting != null;
  bool get canUndo => _index > 0 && !isExporting;
  bool get canRedo => _index + 1 < _history.length && !isExporting;

  void apply(MediaEdit edit) {
    _assertIdle();
    edit.validate(info);
    if (edit == this.edit) return;
    _history.removeRange(_index + 1, _history.length);
    _history.add(MediaEditRevision(_nextId++, edit));
    _index = _history.length - 1;
    // Each recipe is small, but bound history for long desktop sessions.
    if (_history.length > 200) {
      _history.removeAt(0);
      _index--;
    }
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _index--;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _index++;
    notifyListeners();
  }

  MediaEditRevision beginExport() {
    _assertIdle();
    edit.validate(info);
    _exporting = revision;
    notifyListeners();
    return revision;
  }

  /// Only a completed persistence of this exact captured recipe is clean.
  /// Rendering, cancellation, or an upload failure never mark it as exported.
  void finishExport(MediaEditRevision revision, {required bool persisted}) {
    if (!identical(_exporting, revision)) {
      throw StateError('Mismatched media export revision.');
    }
    if (persisted) _savedId = revision.id;
    _exporting = null;
    notifyListeners();
  }

  void _assertIdle() {
    if (isExporting) throw const MediaEditException(MediaEditFailure.busy);
  }
}
