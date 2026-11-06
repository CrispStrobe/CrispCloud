import 'package:flutter/widgets.dart';
import '../services/link_operation_failure.dart';

String localizedLinkError(BuildContext context, Object error) {
  if (error is! LinkOperationFailure) return error.toString();
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final template = (_messages[language] ?? _messages['en']!)[error.code.name];
  if (template == null) return error.toString();
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null ? match.group(0)! : value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {"webUnsupported": "Link creation not supported on Web", "windowsHardlink": "Hard links on Windows require elevated privileges", "hardlinkFailed": "Failed to create hard link: {detail}", "symlinkDenied": "Permission denied creating symlink: {detail}"},
  "de": {"webUnsupported": "Das Erstellen von Links wird im Web nicht unterstützt", "windowsHardlink": "Harte Links unter Windows erfordern erhöhte Rechte", "hardlinkFailed": "Harter Link konnte nicht erstellt werden: {detail}", "symlinkDenied": "Keine Berechtigung zum Erstellen des symbolischen Links: {detail}"},
  "fr": {"webUnsupported": "La création de liens n’est pas prise en charge sur le Web", "windowsHardlink": "Les liens physiques sous Windows nécessitent des privilèges élevés", "hardlinkFailed": "Impossible de créer le lien physique : {detail}", "symlinkDenied": "Autorisation refusée pour créer le lien symbolique : {detail}"},
  "es": {"webUnsupported": "La creación de enlaces no está disponible en la web", "windowsHardlink": "Los enlaces físicos en Windows requieren privilegios elevados", "hardlinkFailed": "No se pudo crear el enlace físico: {detail}", "symlinkDenied": "Permiso denegado al crear el enlace simbólico: {detail}"},
  "pt": {"webUnsupported": "A criação de ligações não é suportada na Web", "windowsHardlink": "As ligações físicas no Windows requerem privilégios elevados", "hardlinkFailed": "Não foi possível criar a ligação física: {detail}", "symlinkDenied": "Permissão negada ao criar a ligação simbólica: {detail}"},
  "zh": {"webUnsupported": "网页端不支持创建链接", "windowsHardlink": "在 Windows 上创建硬链接需要提升权限", "hardlinkFailed": "无法创建硬链接：{detail}", "symlinkDenied": "创建符号链接时权限被拒绝：{detail}"},
  "ja": {"webUnsupported": "Web ではリンクを作成できません", "windowsHardlink": "Windows でハードリンクを作成するには管理者権限が必要です", "hardlinkFailed": "ハードリンクを作成できませんでした: {detail}", "symlinkDenied": "シンボリックリンクの作成が拒否されました: {detail}"},
  "ko": {"webUnsupported": "웹에서는 링크 생성을 지원하지 않습니다", "windowsHardlink": "Windows에서 하드 링크를 만들려면 관리자 권한이 필요합니다", "hardlinkFailed": "하드 링크를 만들 수 없습니다: {detail}", "symlinkDenied": "심볼릭 링크 생성 권한이 거부되었습니다: {detail}"},
  "ar": {"webUnsupported": "إنشاء الروابط غير مدعوم على الويب", "windowsHardlink": "تتطلب الروابط الصلبة على Windows صلاحيات مرتفعة", "hardlinkFailed": "تعذر إنشاء الرابط الصلب: {detail}", "symlinkDenied": "رُفض الإذن بإنشاء الرابط الرمزي: {detail}"},
};
