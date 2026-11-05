import 'package:flutter/widgets.dart';

import '../services/fuse_mount_service.dart';
import '../services/provider_workflow_failure.dart';
import 'mount_error_presentation.dart';

/// Recognizes provider workflow failures without changing external diagnostics.
String? localizedProviderWorkflowError(BuildContext context, Object error) {
  if (error is MountWorkflowFailure) {
    final cause = error.cause;
    final detail = cause is MountEntry
        ? (cause.errorMessage == null && cause.errorKey == null
              ? null
              : localizedMountEntryError(context, cause))
        : cause == null
        ? null
        : localizedMountError(context, cause.toString());
    return localizedProviderWorkflowErrorForLanguage(
      Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
      error,
      detail: detail,
    );
  }
  return localizedProviderWorkflowErrorForLanguage(
    Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
    error,
  );
}

String? localizedProviderWorkflowErrorForLanguage(
  String language,
  Object error, {
  String? detail,
}) {
  final messages = _messages[language] ?? _messages['en']!;
  if (error is TransferFileFailure) {
    return messages[error.code == TransferFileCode.noPath ? 6 : 7];
  }
  if (error is! MountWorkflowFailure) return null;
  if (error.code == MountWorkflowCode.availability) {
    return detail ?? error.cause?.toString() ?? error.message;
  }
  final index = switch (error.code) {
    MountWorkflowCode.unsupported => 0,
    MountWorkflowCode.connectFirst => 1,
    MountWorkflowCode.mount => 2,
    MountWorkflowCode.unmount => 3,
    MountWorkflowCode.remove => 4,
    MountWorkflowCode.availability => throw StateError('Handled above'),
  };
  final cause = error.cause;
  final fallback = cause is MountEntry ? cause.errorMessage : cause?.toString();
  return messages[index].replaceAll(
    '{error}',
    detail ?? fallback ?? messages[5],
  );
}

const _messages = <String, List<String>>{
  'en': [
    "FUSE mounts are not supported on this platform.",
    "Connect to a cloud provider before mounting.",
    "Mount failed: {error}",
    "Unmount failed: {error}",
    "Remove mount failed: {error}",
    "Unknown error",
    "This file has no local path.",
    "The server returned an invalid file name.",
  ],
  'de': [
    "FUSE-Einbindungen werden auf dieser Plattform nicht unterstützt.",
    "Verbinden Sie sich vor dem Einbinden mit einem Cloud-Anbieter.",
    "Einbinden fehlgeschlagen: {error}",
    "Aushängen fehlgeschlagen: {error}",
    "Einbindung konnte nicht entfernt werden: {error}",
    "Unbekannter Fehler",
    "Diese Datei hat keinen lokalen Pfad.",
    "Der Server hat einen ungültigen Dateinamen zurückgegeben.",
  ],
  'fr': [
    "Les montages FUSE ne sont pas pris en charge sur cette plateforme.",
    "Connectez-vous à un fournisseur cloud avant le montage.",
    "Échec du montage : {error}",
    "Échec du démontage : {error}",
    "Impossible de supprimer le montage : {error}",
    "Erreur inconnue",
    "Ce fichier n’a pas de chemin local.",
    "Le serveur a renvoyé un nom de fichier invalide.",
  ],
  'es': [
    "Los montajes FUSE no son compatibles con esta plataforma.",
    "Conéctese a un proveedor en la nube antes de montar.",
    "Error al montar: {error}",
    "Error al desmontar: {error}",
    "Error al eliminar el montaje: {error}",
    "Error desconocido",
    "Este archivo no tiene una ruta local.",
    "El servidor devolvió un nombre de archivo no válido.",
  ],
  'pt': [
    "As montagens FUSE não são suportadas nesta plataforma.",
    "Ligue-se a um fornecedor de nuvem antes de montar.",
    "Falha na montagem: {error}",
    "Falha ao desmontar: {error}",
    "Falha ao remover a montagem: {error}",
    "Erro desconhecido",
    "Este ficheiro não tem um caminho local.",
    "O servidor devolveu um nome de ficheiro inválido.",
  ],
  'zh': [
    "此平台不支持 FUSE 挂载。",
    "挂载前请先连接到云服务提供商。",
    "挂载失败：{error}",
    "卸载失败：{error}",
    "移除挂载失败：{error}",
    "未知错误",
    "此文件没有本地路径。",
    "服务器返回了无效的文件名。",
  ],
  'ja': [
    "このプラットフォームでは FUSE マウントはサポートされていません。",
    "マウントする前にクラウドプロバイダーに接続してください。",
    "マウントに失敗しました: {error}",
    "アンマウントに失敗しました: {error}",
    "マウントの削除に失敗しました: {error}",
    "不明なエラー",
    "このファイルにはローカルパスがありません。",
    "サーバーが無効なファイル名を返しました。",
  ],
  'ko': [
    "이 플랫폼에서는 FUSE 마운트를 지원하지 않습니다.",
    "마운트하기 전에 클라우드 공급자에 연결하세요.",
    "마운트 실패: {error}",
    "마운트 해제 실패: {error}",
    "마운트 제거 실패: {error}",
    "알 수 없는 오류",
    "이 파일에는 로컬 경로가 없습니다.",
    "서버가 잘못된 파일 이름을 반환했습니다.",
  ],
  'ar': [
    "عمليات تركيب FUSE غير مدعومة على هذه المنصة.",
    "اتصل بمزوّد تخزين سحابي قبل التركيب.",
    "فشل التركيب: {error}",
    "فشل إلغاء التركيب: {error}",
    "فشلت إزالة التركيب: {error}",
    "خطأ غير معروف",
    "هذا الملف ليس له مسار محلي.",
    "أعاد الخادم اسم ملف غير صالح.",
  ],
};
