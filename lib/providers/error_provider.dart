// lib/providers/error_provider.dart
//
// Centralized error queue. Widgets watch this to display snackbars/banners.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-authored panel failures with data for localized presentation.
enum PanelErrorCode {
  archiveOpen, archivePassword, archiveRead, flatLocal, flatFailed,
  accessParent, accessDenied, accessContaining, pickFailed, deleteFailed,
  renameFailed, createFailed, moveFailed, copyFailed, selectBase,
  accessCancelled, localUnsupported, permissionDenied,
  cloudTransferFailed, cloudCompareFailed, cloudSearchFailed,
}

class AppError {
  final String message;
  final DateTime timestamp;
  final String? context;
  final PanelErrorCode? code;
  final Object? cause;
  final Map<String, Object> arguments;

  AppError(this.message, {this.context, this.code, this.cause, Map<String, Object> arguments = const {}})
      : arguments = Map.unmodifiable(arguments), timestamp = DateTime.now();

  @override
  String toString() => message;
}

class ErrorNotifier extends ChangeNotifier {
  final List<AppError> _errors = [];

  List<AppError> get errors => List.unmodifiable(_errors);
  String? get lastError => _errors.isEmpty ? null : _errors.last.message;
  AppError? get lastAppError => _errors.isEmpty ? null : _errors.last;
  bool get hasErrors => _errors.isNotEmpty;

  void addError(String message, {String? context, PanelErrorCode? code, Object? cause,
      Map<String, Object> arguments = const {}}) {
    _errors.add(AppError(message, context: context, code: code, cause: cause, arguments: arguments));
    notifyListeners();
  }

  void clearErrors() {
    _errors.clear();
    notifyListeners();
  }

  void clearLastError() {
    if (_errors.isNotEmpty) {
      _errors.removeLast();
      notifyListeners();
    }
  }
}

final errorProvider = ChangeNotifierProvider<ErrorNotifier>((ref) {
  return ErrorNotifier();
});
