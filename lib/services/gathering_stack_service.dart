import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/file_collection.dart';
import '../models/file_item.dart';
import '../models/gathering_stack.dart';
import '../models/storage_reference.dart';
import 'file_collection_service.dart';
import 'file_operation_service.dart';
import 'gathering_stack_store.dart';

typedef GatheringSourceResolver = GatheringSourceBinding? Function(
  StorageReference storage,
  String path,
);

/// Runtime-only original capability. hostContext may carry the corresponding
/// PanelFileOrigin; it is never serialized or used to infer an account.
class GatheringSourceBinding {
  GatheringSourceBinding({
    required this.storage,
    required this.backend,
    this.hostContext,
  }) : _identity = backend.identity;

  final StorageReference storage;
  final FileOperationBackend backend;
  final Object? hostContext;
  final Object _identity;
  bool get isCurrent =>
      backend.isCurrent &&
      backend.identity == _identity &&
      backend.storageReference == storage;
}

class GatheringAddition {
  const GatheringAddition({
    required this.file,
    required this.source,
    this.sessionBound = false,
  });
  final FileItem file;
  final GatheringSourceBinding source;
  final bool sessionBound;
}

/// The destination is captured before any inspection. Before acceptance, a
/// listing change invalidates review. Afterwards only the operation's own
/// refreshes are tolerated; a newer tab/navigation/account intent still stops it.
class GatheringDestinationCapture {
  GatheringDestinationCapture({
    required this.backend,
    required String path,
    required bool Function() isCurrent,
    bool Function()? isReviewCurrent,
    this.hostContext,
  }) : path = backend.paths.normalize(path),
       _isCurrent = isCurrent,
       _isReviewCurrent = isReviewCurrent ?? isCurrent,
       _identity = backend.identity,
       storage = backend.storageReference {
    if (!backend.paths.isAbsolute(this.path) || path.contains('\u0000')) {
      throw const GatheringException(GatheringFailure.destinationChanged);
    }
  }

  final FileOperationBackend backend;
  final String path;
  final StorageReference? storage;
  final Object? hostContext;
  final Object _identity;
  final bool Function() _isCurrent;
  final bool Function() _isReviewCurrent;
  bool _accepted = false;
  bool get isCurrent =>
      _isCurrent() &&
      (_accepted || _isReviewCurrent()) &&
      backend.isCurrent &&
      backend.identity == _identity &&
      backend.storageReference == storage;

  void check() {
    if (!isCurrent) {
      throw const GatheringException(GatheringFailure.destinationChanged);
    }
  }

  void accept() {
    check();
    _accepted = true;
  }

  Future<void> verify() async {
    check();
    // A synthetic root stat cannot establish access to the original account.
    await backend.list(path);
    check();
  }
}

class GatheringCapture {
  GatheringCapture._({
    required this.entries,
    required this.sources,
    required this.destination,
    required bool Function() isCurrent,
    // Keep the capability guard private while naming its purpose at capture.
    // ignore: prefer_initializing_formals
  }) : _isCurrent = isCurrent;

  final List<GatheringStackEntry> entries;
  final Map<String, GatheringSourceBinding?> sources;
  final GatheringDestinationCapture? destination;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent() && (destination?.isCurrent ?? true);

  void check() {
    destination?.check();
    if (!_isCurrent()) {
      throw const GatheringException(GatheringFailure.changed);
    }
  }
}

class GatheringReview {
  GatheringReview._({
    required this.capture,
    required Map<String, FileCollectionEntry> verified,
    required Map<String, GatheringReferenceState> states,
  }) : verified = Map.unmodifiable(verified),
       states = Map.unmodifiable(states);

  final GatheringCapture capture;
  final Map<String, FileCollectionEntry> verified;
  final Map<String, GatheringReferenceState> states;
  bool get canTransfer =>
      capture.entries.isNotEmpty &&
      capture.destination != null &&
      capture.isCurrent &&
      verified.length == capture.entries.length &&
      capture.sources.values.every((source) => source?.isCurrent == true);

  /// Validate the ordinary planner's fresh root snapshots before its preview
  /// becomes executable. It must not silently adopt a replacement which
  /// appeared between the gathering overview and an account's normal review.
  void validatePlan(FileOperationPlan plan) {
    capture.check();
    final destination = capture.destination;
    if (!canTransfer ||
        destination == null ||
        plan.destination.identity != destination.backend.identity ||
        plan.destination.storageReference != destination.storage ||
        !destination.backend.samePath(plan.targetDirectory, destination.path)) {
      throw const GatheringException(GatheringFailure.destinationChanged);
    }
    final relevant = capture.entries.where((entry) {
      final source = capture.sources[entry.id];
      return source?.storage == plan.source.storageReference &&
          source?.backend.identity == plan.source.identity;
    }).toList();
    if (relevant.isEmpty) {
      throw const GatheringException(GatheringFailure.changed);
    }
    for (final item in relevant) {
      for (final entry in plan.entries) {
        if (entry.source.path != null &&
            plan.source.samePath(entry.source.path!, item.reference.path) &&
            !FileCollectionService.sameReplacementEvidence(
              verified[item.id]!,
              entry.source,
            )) {
          throw const GatheringException(GatheringFailure.changed);
        }
      }
    }
  }

  /// Only complete roots are removed. A copied directory alone says nothing
  /// about skipped, filtered, failed, or unfinished descendants. Move roots
  /// additionally require confirmation that the original directory was removed.
  Set<String> successfulIds(FileOperationPlan plan) {
    final destination = capture.destination;
    if (destination == null ||
        plan.destination.identity != destination.backend.identity ||
        plan.destination.storageReference != destination.storage ||
        !destination.backend.samePath(plan.targetDirectory, destination.path)) {
      return const {};
    }
    final successes = <String>{};
    for (final item in capture.entries) {
      final source = capture.sources[item.id];
      final original = verified[item.id];
      if (source == null ||
          original == null ||
          source.storage != plan.source.storageReference ||
          source.backend.identity != plan.source.identity) {
        continue;
      }
      final roots = plan.entries.where(
        (entry) =>
            entry.source.path != null &&
            plan.source.samePath(entry.source.path!, item.reference.path),
      );
      if (roots.length != 1) continue;
      final root = roots.single;
      if (!FileCollectionService.sameReplacementEvidence(
        original,
        root.source,
      )) {
        continue;
      }
      final move = plan.options.kind == FileOperationKind.move;
      if (!root.source.isFolder || root.source.isSymlink == true) {
        if (root.outcome ==
            (move ? FileOperationOutcome.moved : FileOperationOutcome.copied)) {
          successes.add(item.id);
        }
        continue;
      }
      if (!plan.options.recursive ||
          root.outcome !=
              (move
                  ? FileOperationOutcome.moved
                  : FileOperationOutcome.directoryCreated) ||
          (plan.options.requestsMetadataPreservation &&
              root.recovery?['directoryMetadataApplied'] != true)) {
        continue;
      }
      final complete = plan.entries
          .where(
            (entry) =>
                entry.source.path != null &&
                plan.source.isWithin(item.reference.path, entry.source.path!),
          )
          .every(
            (entry) => move
                ? entry.outcome == FileOperationOutcome.moved
                : entry.outcome == FileOperationOutcome.copied ||
                      entry.outcome == FileOperationOutcome.directoryCreated,
          );
      if (complete) successes.add(item.id);
    }
    return successes;
  }
}

class GatheringStackService {
  GatheringStackService(this.store);
  final GatheringStackStore store;
  final _sessionSources = <String, GatheringSourceBinding>{};
  int _request = 0;

  Future<GatheringAddResult> add(
    Iterable<GatheringAddition> additions, {
    bool Function()? isCurrent,
  }) async {
    final incoming = List<GatheringAddition>.unmodifiable(
      additions.take(GatheringStackStore.maximumEntries + 1),
    );
    if (incoming.length > GatheringStackStore.maximumEntries) {
      throw const GatheringException(GatheringFailure.limit);
    }
    final rows = <GatheringStackEntry>[];
    final sources = <String, GatheringSourceBinding>{};
    for (final addition in incoming) {
      final source = addition.source;
      final path = addition.file.path;
      if (!source.isCurrent || path == null) {
        throw const GatheringException(GatheringFailure.unavailable);
      }
      final id = const Uuid().v4();
      rows.add(
        GatheringStackEntry(
          id: id,
          original: FileCollectionService.capture(
            addition.file.copyWith(path: source.backend.paths.normalize(path)),
            source.storage,
          ),
          sessionBound: addition.sessionBound || !source.storage.persistent,
        ),
      );
      sources[id] = source;
    }
    final result = await store.add(
      rows,
      isCurrent: () =>
          (isCurrent?.call() ?? true) &&
          sources.values.every((source) => source.isCurrent),
    );
    final live = store.entries.map((entry) => entry.id).toSet();
    _sessionSources.removeWhere((id, _) => !live.contains(id));
    for (final entry in sources.entries) {
      if (live.contains(entry.key)) _sessionSources[entry.key] = entry.value;
    }
    return result;
  }

  /// Resolve every account and grant synchronously, before the first await.
  /// A later reconnect can only be used by an explicit, newer verification.
  GatheringCapture capture({
    required GatheringSourceResolver resolve,
    GatheringDestinationCapture? destination,
    bool Function()? isCurrent,
  }) {
    if (store.isLoading || store.loadError != null) {
      throw const GatheringException(GatheringFailure.storageFailure);
    }
    final request = ++_request;
    final intent = store.intentRevision;
    final entries = List<GatheringStackEntry>.unmodifiable(store.entries);
    final sources = <String, GatheringSourceBinding?>{};
    for (final entry in entries) {
      GatheringSourceBinding? source;
      if (entry.sessionBound) {
        source = _sessionSources[entry.id];
      } else {
        source = resolve(entry.reference.storage, entry.reference.path);
      }
      sources[entry.id] = source?.storage == entry.reference.storage
          ? source
          : null;
    }
    return GatheringCapture._(
      entries: entries,
      sources: Map.unmodifiable(sources),
      destination: destination,
      isCurrent: () =>
          request == _request &&
          intent == store.intentRevision &&
          (isCurrent?.call() ?? true),
    );
  }

  Future<GatheringReview> verify(
    GatheringCapture capture, {
    required FileOperationControl control,
    Duration timeout = const Duration(seconds: 30),
    void Function(int completed, int total)? onProgress,
  }) async {
    void check() {
      if (control.isCancelled) {
        throw const GatheringException(GatheringFailure.cancelled);
      }
      capture.check();
    }

    Future<GatheringReview> inspect() async {
      check();
      final verified = <String, FileCollectionEntry>{};
      final states = <String, GatheringReferenceState>{};
      if (capture.destination != null) await capture.destination!.verify();
      check();
      // Existing collection refresh shares bounded directory snapshots. Split
      // duplicate path records (different saved objects) into separate batches.
      final remaining = List<GatheringStackEntry>.of(capture.entries);
      while (remaining.isNotEmpty) {
        check();
        final keys = <String>{};
        final namespaces = <String, String>{};
        final batch = <GatheringStackEntry>[];
        for (final entry in remaining) {
          if (batch.length >= 128) break;
          final storage = entry.reference.storage;
          final previousRoot = namespaces[storage.id];
          if (previousRoot != null && previousRoot != storage.root) continue;
          namespaces[storage.id] = storage.root;
          if (keys.add(entry.original.key)) batch.add(entry);
        }
        final byKey = {for (final entry in batch) entry.original.key: entry};
        final result = await const FileCollectionService().refresh(
          FileCollection(
            id: 'gathering-verification',
            name: 'Gathering verification',
            entries: batch.map((entry) => entry.original).toList(),
          ),
          (storage, path) {
            final item = byKey['${storage.id}\u0000$path'];
            final source = capture.sources[item?.id];
            return source?.isCurrent == true ? source!.backend : null;
          },
          isCancelled: () => control.isCancelled || !capture.isCurrent,
        );
        check();
        for (final entry in result.collection.entries) {
          final item = byKey[entry.key]!;
          final source = capture.sources[item.id];
          states[item.id] = item.sessionBound && source == null
              ? GatheringReferenceState.sessionOnly
              : switch (entry.state) {
                  CollectionItemState.ready => GatheringReferenceState.ready,
                  CollectionItemState.changed =>
                    entry.replacement
                        ? GatheringReferenceState.replaced
                        : GatheringReferenceState.changed,
                  CollectionItemState.missing =>
                    GatheringReferenceState.missing,
                  CollectionItemState.offline =>
                    GatheringReferenceState.offline,
                };
          if (result.verifiedKeys.contains(entry.key) &&
              source?.isCurrent == true) {
            verified[item.id] = entry;
          }
        }
        remaining.removeWhere((entry) => batch.contains(entry));
        store.recordStates(capture.entries, states);
        onProgress?.call(
          capture.entries.length - remaining.length,
          capture.entries.length,
        );
      }
      check();
      for (final entry in capture.entries) {
        if (capture.sources[entry.id]?.isCurrent != true &&
            verified.remove(entry.id) != null) {
          states[entry.id] = GatheringReferenceState.offline;
        }
      }
      store.recordStates(capture.entries, states);
      return GatheringReview._(
        capture: capture,
        verified: verified,
        states: states,
      );
    }

    try {
      return await Future.any([
        inspect(),
        control.cancellationFuture.then<GatheringReview>((_) {
          throw const GatheringException(GatheringFailure.cancelled);
        }),
      ]).timeout(timeout);
    } on TimeoutException {
      control.cancel();
      throw const GatheringException(GatheringFailure.unavailable);
    } catch (_) {
      check();
      rethrow;
    }
  }

  Future<int> reconcile(GatheringReview review, FileOperationPlan plan) async {
    final removed = await store.removeConfirmed(
      review.capture.entries,
      review.successfulIds(plan),
    );
    if (removed > 0 && !review.capture.isCurrent) {
      // A newer overview may have captured these rows before this older
      // operation settled. Invalidate that overview instead of allowing a
      // second transfer of references which just left the stack. The active
      // review's own per-group cleanup deliberately keeps its request current.
      _request++;
    }
    return removed;
  }
}
