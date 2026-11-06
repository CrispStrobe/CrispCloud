import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'file_collection_storage.dart';

FileCollectionStorage createFileCollectionStorage({
  required Future<SharedPreferences> Function() preferences,
}) => BrowserFileCollectionStorage();

/// One IndexedDB value per bounded row page; browsing the catalog never loads
/// file payloads into browser localStorage or SharedPreferences.
class BrowserFileCollectionStorage implements FileCollectionStorage {
  Future<web.IDBDatabase>? _database;
  Future<web.IDBDatabase> _open() => _database ??= () async {
    final done = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open('crispcloud_collections_v2', 1);
    request.onupgradeneeded = ((web.Event event) {
      (request.result as web.IDBDatabase).createObjectStore('records');
    }).toJS;
    request.onsuccess = ((web.Event event) {
      if (!done.isCompleted) {
        done.complete(request.result as web.IDBDatabase);
      }
    }).toJS;
    request.onerror = ((web.Event event) {
      if (!done.isCompleted) {
        done.completeError(
          StateError(
            'Collection database is unavailable: ${request.error?.message}',
          ),
        );
      }
    }).toJS;
    request.onblocked = ((web.Event event) {
      if (!done.isCompleted) {
        done.completeError(
          StateError(
            'Close another CrispCloud tab to open collection storage.',
          ),
        );
      }
    }).toJS;
    return done.future;
  }();

  Future<JSAny?> _readRequest(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event event) => done.complete(
      request.result,
    )).toJS;
    request.onerror = ((web.Event event) => done.completeError(
      StateError(
        'Could not read collection storage: ${request.error?.message}',
      ),
    )).toJS;
    return done.future;
  }

  Future<void> _committed(web.IDBTransaction transaction) {
    final done = Completer<void>();
    transaction.oncomplete = ((web.Event event) {
      if (!done.isCompleted) {
        done.complete();
      }
    }).toJS;
    void failed(web.Event event) {
      if (!done.isCompleted) {
        done.completeError(
          StateError(
            'Collection storage write failed: ${transaction.error?.message}',
          ),
        );
      }
    }

    transaction.onerror = failed.toJS;
    transaction.onabort = failed.toJS;
    return done.future;
  }

  @override
  Future<String?> read(String key, {required int maxBytes}) async {
    final database = await _open();
    final transaction = database.transaction('records'.toJS, 'readonly');
    final result = await _readRequest(
      transaction.objectStore('records').get(key.toJS),
    );
    if (result == null || result.isUndefinedOrNull) {
      return null;
    }
    final value = (result as JSString).toDart;
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException(
        'Saved collection record exceeds its size limit.',
      );
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    final transaction = (await _open()).transaction(
      'records'.toJS,
      'readwrite',
    );
    final complete = _committed(transaction);
    transaction.objectStore('records').put(value.toJS, key.toJS);
    await complete;
  }

  @override
  Future<void> remove(String key) async {
    final transaction = (await _open()).transaction(
      'records'.toJS,
      'readwrite',
    );
    final complete = _committed(transaction);
    transaction.objectStore('records').delete(key.toJS);
    await complete;
  }

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final transaction = (await _open()).transaction(
      'records'.toJS,
      'readwrite',
    );
    final complete = _committed(transaction);
    final store = transaction.objectStore('records');
    final request = store.get(key.toJS);
    var accepted = false;
    request.onsuccess = ((web.Event event) {
      final result = request.result;
      final current = result == null || result.isUndefinedOrNull
          ? null
          : (result as JSString).toDart;
      if (current == expected) {
        accepted = true;
        store.put(value.toJS, key.toJS);
      }
    }).toJS;
    await complete;
    return accepted;
  }
}
