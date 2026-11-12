import 'dart:convert';

import 'package:path/path.dart' as p;

import 'file_collection.dart';
import 'file_item.dart';
import 'storage_reference.dart';

enum GatheringReferenceState {
  unchecked,
  ready,
  changed,
  missing,
  offline,
  replaced,
  sessionOnly,
}

enum GatheringFailure {
  empty,
  limit,
  invalidReference,
  unavailable,
  changed,
  cancelled,
  destinationChanged,
  storageFailure,
}

class GatheringException implements Exception {
  const GatheringException(this.failure);
  final GatheringFailure failure;
  @override
  String toString() => 'Gathering stack: ${failure.name}';
}

/// A reference and a bounded display snapshot, never file bytes or a grant.
/// A new ticket is issued when an item is gathered again. A late completion
/// can therefore never remove the newer reference, even at the same path.
class GatheringStackEntry {
  GatheringStackEntry({
    required this.id,
    required FileCollectionEntry original,
    this.sessionBound = false,
  }) : original = FileCollectionEntry(
         reference: original.reference,
         file: FileItem(
           name: original.file.name,
           path: original.reference.path,
           uuid: original.reference.objectId,
           storageId: original.reference.storage.id,
           isFolder: original.file.isFolder,
           size: original.file.size,
           updatedAt: original.file.updatedAt,
           isSymlink: original.file.isSymlink,
           symlinkTarget: original.file.symlinkTarget,
         ),
       ) {
    final reference = original.reference;
    final paths =
        reference.storage.isLocal &&
            reference.storage.provider.toLowerCase() == 'windows'
        ? p.windows
        : p.posix;
    if (id.isEmpty ||
        id.length > 128 ||
        original.file.name.isEmpty ||
        const ['.', '..'].contains(original.file.name) ||
        !paths.isAbsolute(reference.path) ||
        reference.path.contains('\u0000') ||
        reference.path.length > 32768 ||
        reference.path != paths.normalize(reference.path) ||
        reference.storage.root.contains('\u0000')) {
      throw const GatheringException(GatheringFailure.invalidReference);
    }
  }

  final String id;
  final FileCollectionEntry original;

  /// Browser grants and anonymous sessions cannot be restored by a saved path.
  final bool sessionBound;
  FileReference get reference => original.reference;

  /// Stable object identity wins when supplied; otherwise the exact normalized
  /// path is used. Case-distinct paths are not collapsed by filename matching.
  String get identityKey => jsonEncode([
    reference.storage.id,
    reference.storage.root,
    reference.objectId == null
        ? ['path', reference.path]
        : ['object', reference.objectId],
  ]);

  String get evidenceKey => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'original': original.toJson(),
    'sessionBound': sessionBound,
  };

  factory GatheringStackEntry.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String || json['original'] is! Map) {
      throw const GatheringException(GatheringFailure.invalidReference);
    }
    return GatheringStackEntry(
      id: json['id'] as String,
      original: FileCollectionEntry.fromJson(
        Map<String, dynamic>.from(json['original'] as Map),
      ),
      sessionBound: json['sessionBound'] == true,
    );
  }
}

class GatheringAddResult {
  const GatheringAddResult({required this.added, required this.refreshed});
  final int added;
  final int refreshed;
}
