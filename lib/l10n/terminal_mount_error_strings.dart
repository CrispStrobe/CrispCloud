import 'package:flutter/widgets.dart';
import '../services/terminal_mount_failure.dart';
import 'provider_operation_strings.dart';

String localizedTerminalMountError(BuildContext context, Object error) =>
    localizedTerminalMountErrorForLanguage(
      Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
      error,
    );

String localizedTerminalMountErrorForLanguage(String language, Object error) {
  if (error is! TerminalMountFailure)
    return localizedProviderErrorForLanguage(language, error);
  final template = (_messages[language] ?? _messages['en']!)[error.code.name]!;
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    if (value == null) return match.group(0)!;
    return value is TerminalMountFailure
        ? localizedTerminalMountErrorForLanguage(language, value)
        : localizedProviderErrorForLanguage(language, value);
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {
    "sshPoolFull": "SSH session pool is full (max {max} concurrent sessions).",
    "sshDisconnected": "Session {session} is not connected",
    "sshNoShell": "No active shell for session {session}",
    "sshUnknownSession": "Unknown session id: {session}",

    "sshUnsupported": "SSH terminal is not supported on web.",
    "sshConnection": "SSH connection failed: {error}",
    "sshKeyConnection": "SSH key-based connection failed: {error}",
    "sshInvalidKey": "Invalid SSH private key",
    "sshCommand": "Command execution failed: {error}",
    "mountDuplicate": "Mount point \"{path}\" is already mounted",
    "mountUnsupported":
        "FUSE mounts are only available on macOS, Linux, and Windows desktop.",
  },
  "de": {
    "sshPoolFull":
        "Der SSH-Sitzungspool ist voll (maximal {max} gleichzeitige Sitzungen).",
    "sshDisconnected": "Sitzung {session} ist nicht verbunden",
    "sshNoShell": "Keine aktive Shell für Sitzung {session}",
    "sshUnknownSession": "Unbekannte Sitzungs-ID: {session}",

    "sshUnsupported": "Das SSH-Terminal wird im Web nicht unterstützt.",
    "sshConnection": "SSH-Verbindung fehlgeschlagen: {error}",
    "sshKeyConnection": "SSH-Verbindung mit Schlüssel fehlgeschlagen: {error}",
    "sshInvalidKey": "Ungültiger privater SSH-Schlüssel",
    "sshCommand": "Befehlsausführung fehlgeschlagen: {error}",
    "mountDuplicate": "Einhängepunkt „{path}“ ist bereits eingehängt",
    "mountUnsupported":
        "FUSE-Laufwerke sind nur auf macOS-, Linux- und Windows-Desktops verfügbar.",
  },
  "fr": {
    "sshPoolFull":
        "Le nombre maximal de sessions SSH est atteint ({max} simultanées).",
    "sshDisconnected": "La session {session} n’est pas connectée",
    "sshNoShell": "Aucun shell actif pour la session {session}",
    "sshUnknownSession": "Identifiant de session inconnu : {session}",

    "sshUnsupported": "Le terminal SSH n’est pas disponible sur le Web.",
    "sshConnection": "Échec de connexion SSH : {error}",
    "sshKeyConnection": "Échec de connexion SSH par clé : {error}",
    "sshInvalidKey": "Clé privée SSH invalide",
    "sshCommand": "Échec de la commande : {error}",
    "mountDuplicate": "Le point de montage « {path} » est déjà monté",
    "mountUnsupported":
        "Les montages FUSE sont disponibles uniquement sur macOS, Linux et Windows.",
  },
  "es": {
    "sshPoolFull": "Se alcanzó el máximo de sesiones SSH ({max} simultáneas).",
    "sshDisconnected": "La sesión {session} no está conectada",
    "sshNoShell": "No hay una consola activa para la sesión {session}",
    "sshUnknownSession": "Identificador de sesión desconocido: {session}",

    "sshUnsupported": "El terminal SSH no es compatible con la web.",
    "sshConnection": "Error de conexión SSH: {error}",
    "sshKeyConnection": "Error de conexión SSH con clave: {error}",
    "sshInvalidKey": "Clave privada SSH no válida",
    "sshCommand": "Error al ejecutar el comando: {error}",
    "mountDuplicate": "El punto de montaje «{path}» ya está montado",
    "mountUnsupported":
        "Los montajes FUSE solo están disponibles en macOS, Linux y Windows de escritorio.",
  },
  "pt": {
    "sshPoolFull":
        "Foi atingido o limite de sessões SSH ({max} em simultâneo).",
    "sshDisconnected": "A sessão {session} não está ligada",
    "sshNoShell": "Não há shell ativa para a sessão {session}",
    "sshUnknownSession": "ID de sessão desconhecido: {session}",

    "sshUnsupported": "O terminal SSH não é suportado na Web.",
    "sshConnection": "Falha na ligação SSH: {error}",
    "sshKeyConnection": "Falha na ligação SSH com chave: {error}",
    "sshInvalidKey": "Chave privada SSH inválida",
    "sshCommand": "Falha na execução do comando: {error}",
    "mountDuplicate": "O ponto de montagem «{path}» já está montado",
    "mountUnsupported":
        "As montagens FUSE só estão disponíveis em macOS, Linux e Windows de ambiente de trabalho.",
  },
  "zh": {
    "sshPoolFull": "SSH 会话已满（最多同时 {max} 个会话）。",
    "sshDisconnected": "会话 {session} 未连接",
    "sshNoShell": "会话 {session} 没有活动的终端",
    "sshUnknownSession": "未知会话 ID：{session}",

    "sshUnsupported": "网页端不支持 SSH 终端。",
    "sshConnection": "SSH 连接失败：{error}",
    "sshKeyConnection": "SSH 密钥连接失败：{error}",
    "sshInvalidKey": "SSH 私钥无效",
    "sshCommand": "命令执行失败：{error}",
    "mountDuplicate": "挂载点“{path}”已挂载",
    "mountUnsupported": "FUSE 挂载仅适用于 macOS、Linux 和 Windows 桌面。",
  },
  "ja": {
    "sshPoolFull": "SSH セッションが上限に達しました（同時に最大 {max} 件）。",
    "sshDisconnected": "セッション {session} は接続されていません",
    "sshNoShell": "セッション {session} に有効なシェルがありません",
    "sshUnknownSession": "不明なセッション ID: {session}",

    "sshUnsupported": "Web では SSH ターミナルを使用できません。",
    "sshConnection": "SSH 接続に失敗しました: {error}",
    "sshKeyConnection": "SSH 鍵接続に失敗しました: {error}",
    "sshInvalidKey": "SSH 秘密鍵が無効です",
    "sshCommand": "コマンドの実行に失敗しました: {error}",
    "mountDuplicate": "マウントポイント「{path}」は既にマウントされています",
    "mountUnsupported": "FUSE マウントは macOS、Linux、Windows のデスクトップでのみ使用できます。",
  },
  "ko": {
    "sshPoolFull": "SSH 세션이 가득 찼습니다 (동시 최대 {max}개).",
    "sshDisconnected": "세션 {session}이 연결되지 않았습니다",
    "sshNoShell": "세션 {session}에 활성 셸이 없습니다",
    "sshUnknownSession": "알 수 없는 세션 ID: {session}",

    "sshUnsupported": "웹에서는 SSH 터미널을 지원하지 않습니다.",
    "sshConnection": "SSH 연결 실패: {error}",
    "sshKeyConnection": "SSH 키 연결 실패: {error}",
    "sshInvalidKey": "잘못된 SSH 개인 키",
    "sshCommand": "명령 실행 실패: {error}",
    "mountDuplicate": "마운트 지점 \"{path}\"이 이미 마운트되어 있습니다",
    "mountUnsupported": "FUSE 마운트는 macOS, Linux 및 Windows 데스크톱에서만 사용할 수 있습니다.",
  },
  "ar": {
    "sshPoolFull": "بلغت جلسات SSH الحد الأقصى ({max} جلسات متزامنة).",
    "sshDisconnected": "الجلسة {session} غير متصلة",
    "sshNoShell": "لا توجد واجهة أوامر نشطة للجلسة {session}",
    "sshUnknownSession": "معرّف الجلسة غير معروف: {session}",

    "sshUnsupported": "طرفية SSH غير مدعومة على الويب.",
    "sshConnection": "فشل اتصال SSH: {error}",
    "sshKeyConnection": "فشل اتصال SSH باستخدام المفتاح: {error}",
    "sshInvalidKey": "مفتاح SSH الخاص غير صالح",
    "sshCommand": "فشل تنفيذ الأمر: {error}",
    "mountDuplicate": "نقطة التحميل «{path}» محمّلة بالفعل",
    "mountUnsupported":
        "تتوفر نقاط تحميل FUSE على أجهزة macOS وLinux وWindows فقط.",
  },
};
