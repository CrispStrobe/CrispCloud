import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/credential_storage_diagnostics.dart';

/// Selectable, bounded diagnostics available even before a profile unlocks.
class CredentialStorageDiagnosticsView extends StatelessWidget {
  const CredentialStorageDiagnosticsView({
    super.key,
    required this.diagnostics,
  });
  final CredentialStorageDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final labels =
        _labels[Localizations.maybeLocaleOf(context)?.languageCode] ??
        _labels['en']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          '${labels[0]}: ${diagnostics.store}\n'
          '${labels[1]}: ${diagnostics.location}\n'
          '${labels[2]}: ${diagnostics.operation}\n'
          '${labels[3]}: ${diagnostics.errorType}${diagnostics.code == null ? '' : ' / ${diagnostics.code}'}\n'
          '${diagnostics.message}',
        ),
        ExpansionTile(
          title: Text(labels[4]),
          children: [
            SelectableText(diagnostics.report),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: diagnostics.report)),
              icon: const Icon(Icons.copy),
              label: Text(labels[5]),
            ),
          ],
        ),
      ],
    );
  }

  static const _labels = <String, List<String>>{
    'en': [
      'Credential store',
      'Location',
      'Failed operation',
      'Error',
      'Technical details and original stack trace',
      'Copy diagnostics',
    ],
    'de': [
      'Zugangsdaten-Speicher',
      'Speicherort',
      'Fehlgeschlagener Vorgang',
      'Fehler',
      'Technische Details und ursprünglicher Stacktrace',
      'Diagnose kopieren',
    ],
    'fr': [
      'Stockage des identifiants',
      'Emplacement',
      'Opération échouée',
      'Erreur',
      'Détails techniques et trace de pile d’origine',
      'Copier le diagnostic',
    ],
    'es': [
      'Almacén de credenciales',
      'Ubicación',
      'Operación fallida',
      'Error',
      'Detalles técnicos y traza original',
      'Copiar diagnóstico',
    ],
    'pt': [
      'Armazenamento de credenciais',
      'Localização',
      'Operação que falhou',
      'Erro',
      'Detalhes técnicos e rastreamento original',
      'Copiar diagnóstico',
    ],
    'zh': ['凭据存储', '位置', '失败的操作', '错误', '技术详情和原始堆栈跟踪', '复制诊断信息'],
    'ja': ['認証情報ストレージ', '場所', '失敗した操作', 'エラー', '技術情報と元のスタックトレース', '診断情報をコピー'],
    'ko': ['자격 증명 저장소', '위치', '실패한 작업', '오류', '기술 정보 및 원본 스택 추적', '진단 정보 복사'],
    'ru': [
      'Хранилище учётных данных',
      'Расположение',
      'Неудачная операция',
      'Ошибка',
      'Технические сведения и исходный стек вызовов',
      'Копировать диагностику',
    ],
  };
}
