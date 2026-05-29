// lib/providers/error_provider.dart
//
// Centralized error queue. Widgets watch this to display snackbars/banners.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppError {
  final String message;
  final DateTime timestamp;
  final String? context;

  AppError(this.message, {this.context}) : timestamp = DateTime.now();

  @override
  String toString() => message;
}

class ErrorNotifier extends ChangeNotifier {
  final List<AppError> _errors = [];

  List<AppError> get errors => List.unmodifiable(_errors);
  String? get lastError => _errors.isEmpty ? null : _errors.last.message;
  bool get hasErrors => _errors.isNotEmpty;

  void addError(String message, {String? context}) {
    _errors.add(AppError(message, context: context));
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
