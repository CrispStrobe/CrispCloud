import 'package:flutter/widgets.dart';

import '../services/office_pdf_service.dart';
import 'file_bytes_error_strings.dart';

/// Formats app-authored Office layout failures and preserves their causes.
String localizedOfficePdfError(BuildContext context, Object error) {
  if (error is! OfficePdfException) {
    return localizedFileBytesError(context, error);
  }
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final messages = _messages[language] ?? _messages['en']!;
  if (error.sizeBytes != null) {
    final size = (error.sizeBytes! / (1024 * 1024)).toStringAsFixed(1);
    return messages[0].replaceAll('{size}', size);
  }
  if (error.cause != null) {
    return messages[1].replaceAll(
      '{error}',
      localizedFileBytesError(context, error.cause!),
    );
  }
  return error.message;
}

const _messages = <String, List<String>>{
  'en': [
    'This document is too large to lay out safely ({size} MB).',
    'Could not lay out this document: {error}',
  ],
  'de': [
    'Dieses Dokument ist zu groß für eine sichere Seitengestaltung ({size} MB).',
    'Das Dokument konnte nicht gestaltet werden: {error}',
  ],
  'fr': [
    'Ce document est trop volumineux pour une mise en page sûre ({size} Mo).',
    'Impossible de mettre ce document en page : {error}',
  ],
  'es': [
    'Este documento es demasiado grande para maquetarlo de forma segura ({size} MB).',
    'No se pudo maquetar este documento: {error}',
  ],
  'pt': [
    'Este documento é demasiado grande para paginação segura ({size} MB).',
    'Não foi possível paginar este documento: {error}',
  ],
  'zh': ['此文档过大，无法安全排版（{size} MB）。', '无法排版此文档：{error}'],
  'ja': [
    'この文書は大きすぎるため、安全にレイアウトできません（{size} MB）。',
    'この文書をレイアウトできませんでした: {error}',
  ],
  'ko': [
    '이 문서는 크기가 너무 커서 안전하게 배치할 수 없습니다 ({size} MB).',
    '이 문서를 배치할 수 없습니다: {error}',
  ],
  'ar': [
    'المستند كبير جدًا بحيث يتعذر تنسيقه بأمان ({size} ميغابايت).',
    'تعذر تنسيق هذا المستند: {error}',
  ],
};
