import 'package:flutter/widgets.dart';
import '../models/operation_progress.dart';

/// Render app-authored transfer errors without modifying provider details.
class TransferErrorStrings {
  TransferErrorStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key, [Map<String, Object> values = const {}]) {
    var result = (_messages[language] ?? _messages['en']!)[key] ??
        _messages['en']![key]!;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  String? error(OperationProgress operation) {
    final code = operation.errorCode;
    return code == null
        ? operation.error
        : text(code.name, operation.errorArguments);
  }

  static const Map<String, Map<String, String>> _messages = {
    'en': {
      "cancelled": "Cancelled by user",
      "allFilesFailed": "All files failed",
      "someFilesFailed": "{failed} of {total} files failed",
      "batchFiles": "{count} files",
    },
    'de': {
      "cancelled": "Vom Benutzer abgebrochen",
      "allFilesFailed": "Alle Dateien fehlgeschlagen",
      "someFilesFailed": "{failed} von {total} Dateien fehlgeschlagen",
      "batchFiles": "{count} Dateien",
    },
    'fr': {
      "cancelled": "Annulé par l’utilisateur",
      "allFilesFailed": "Échec pour tous les fichiers",
      "someFilesFailed": "Échec pour {failed} fichiers sur {total}",
      "batchFiles": "{count} fichiers",
    },
    'es': {
      "cancelled": "Cancelado por el usuario",
      "allFilesFailed": "Fallaron todos los archivos",
      "someFilesFailed": "Fallaron {failed} de {total} archivos",
      "batchFiles": "{count} archivos",
    },
    'pt': {
      "cancelled": "Cancelado pelo usuário",
      "allFilesFailed": "Todos os arquivos falharam",
      "someFilesFailed": "Falha em {failed} de {total} arquivos",
      "batchFiles": "{count} arquivos",
    },
    'zh': {
      "cancelled": "用户已取消",
      "allFilesFailed": "所有文件均失败",
      "someFilesFailed": "{total} 个文件中有 {failed} 个失败",
      "batchFiles": "{count} 个文件",
    },
    'ja': {
      "cancelled": "ユーザーがキャンセルしました",
      "allFilesFailed": "すべてのファイルが失敗しました",
      "someFilesFailed": "{total} ファイル中 {failed} 件が失敗しました",
      "batchFiles": "{count} ファイル",
    },
    'ko': {
      "cancelled": "사용자가 취소함",
      "allFilesFailed": "모든 파일 실패",
      "someFilesFailed": "파일 {total}개 중 {failed}개 실패",
      "batchFiles": "파일 {count}개",
    },
    'ar': {
      "cancelled": "ألغاه المستخدم",
      "allFilesFailed": "فشلت جميع الملفات",
      "someFilesFailed": "فشل {failed} من أصل {total} ملف",
      "batchFiles": "الملفات: {count}",
    },
  };
}
