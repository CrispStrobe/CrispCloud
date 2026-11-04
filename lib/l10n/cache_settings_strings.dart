import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Text for cache usage and settings.
class CacheSettingsStrings {
  CacheSettingsStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key, [Map<String, Object> values = const {}]) {
    var result =
        (_strings[language] ?? _strings['en']!)[key] ?? _strings['en']![key]!;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  String files(int count) {
    final key = Intl.plural(count,
        locale: language,
        zero: 'fileZero',
        one: 'fileOne',
        two: 'fileTwo',
        few: 'fileFew',
        many: 'fileMany',
        other: 'fileOther');
    return text(key, {'count': count});
  }

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      "settings": "Cache Settings",
      "clearTitle": "Clear Cache",
      "clearConfirm":
          "Remove all cached files? They will be re-downloaded when needed.",
      "unlimited": "Unlimited",
      "usage": "Cache Usage",
      "usedUnlimited": "{used} used (Unlimited)",
      "usedLimit": "{used} / {max} used",
      "max": "Maximum Cache Size",
      "eviction":
          "Least recently used files are evicted when the limit is reached.",
      "fileOne": "{count} file",
      "fileOther": "{count} files",
      "fileZero": "{count} files",
      "fileTwo": "{count} files",
      "fileFew": "{count} files",
      "fileMany": "{count} files",
    },
    'de': {
      "settings": "Cache-Einstellungen",
      "clearTitle": "Cache leeren",
      "clearConfirm":
          "Alle zwischengespeicherten Dateien entfernen? Sie werden bei Bedarf erneut heruntergeladen.",
      "unlimited": "Unbegrenzt",
      "usage": "Cache-Nutzung",
      "usedUnlimited": "{used} verwendet (unbegrenzt)",
      "usedLimit": "{used} / {max} verwendet",
      "max": "Maximale Cache-Größe",
      "eviction":
          "Bei Erreichen des Limits werden die am längsten nicht verwendeten Dateien entfernt.",
      "fileOne": "{count} Datei",
      "fileOther": "{count} Dateien",
      "fileZero": "{count} Dateien",
      "fileTwo": "{count} Dateien",
      "fileFew": "{count} Dateien",
      "fileMany": "{count} Dateien",
    },
    'fr': {
      "settings": "Paramètres du cache",
      "clearTitle": "Vider le cache",
      "clearConfirm":
          "Supprimer tous les fichiers en cache ? Ils seront téléchargés à nouveau si nécessaire.",
      "unlimited": "Illimité",
      "usage": "Utilisation du cache",
      "usedUnlimited": "{used} utilisés (illimité)",
      "usedLimit": "{used} / {max} utilisés",
      "max": "Taille maximale du cache",
      "eviction":
          "À la limite, les fichiers les moins récemment utilisés sont supprimés.",
      "fileOne": "{count} fichier",
      "fileOther": "{count} fichiers",
      "fileZero": "{count} fichiers",
      "fileTwo": "{count} fichiers",
      "fileFew": "{count} fichiers",
      "fileMany": "{count} fichiers",
    },
    'es': {
      "settings": "Configuración de caché",
      "clearTitle": "Vaciar caché",
      "clearConfirm":
          "¿Eliminar todos los archivos de la caché? Se descargarán de nuevo cuando sea necesario.",
      "unlimited": "Ilimitado",
      "usage": "Uso de caché",
      "usedUnlimited": "{used} usados (ilimitado)",
      "usedLimit": "{used} / {max} usados",
      "max": "Tamaño máximo de caché",
      "eviction":
          "Al alcanzar el límite se eliminan los archivos usados hace más tiempo.",
      "fileOne": "{count} archivo",
      "fileOther": "{count} archivos",
      "fileZero": "{count} archivos",
      "fileTwo": "{count} archivos",
      "fileFew": "{count} archivos",
      "fileMany": "{count} archivos",
    },
    'pt': {
      "settings": "Configurações de cache",
      "clearTitle": "Limpar cache",
      "clearConfirm":
          "Remover todos os arquivos em cache? Eles serão baixados novamente quando necessário.",
      "unlimited": "Ilimitado",
      "usage": "Uso do cache",
      "usedUnlimited": "{used} usados (ilimitado)",
      "usedLimit": "{used} / {max} usados",
      "max": "Tamanho máximo do cache",
      "eviction":
          "Ao atingir o limite, os arquivos usados há mais tempo são removidos.",
      "fileOne": "{count} arquivo",
      "fileOther": "{count} arquivos",
      "fileZero": "{count} arquivos",
      "fileTwo": "{count} arquivos",
      "fileFew": "{count} arquivos",
      "fileMany": "{count} arquivos",
    },
    'zh': {
      "settings": "缓存设置",
      "clearTitle": "清除缓存",
      "clearConfirm": "删除所有缓存文件？需要时将重新下载。",
      "unlimited": "无限制",
      "usage": "缓存使用量",
      "usedUnlimited": "已使用 {used}（无限制）",
      "usedLimit": "已使用 {used} / {max}",
      "max": "最大缓存大小",
      "eviction": "达到上限时，将清除最久未使用的文件。",
      "fileOne": "{count} 个文件",
      "fileOther": "{count} 个文件",
      "fileZero": "{count} 个文件",
      "fileTwo": "{count} 个文件",
      "fileFew": "{count} 个文件",
      "fileMany": "{count} 个文件",
    },
    'ja': {
      "settings": "キャッシュ設定",
      "clearTitle": "キャッシュを消去",
      "clearConfirm": "キャッシュされたファイルをすべて削除しますか？必要に応じて再ダウンロードされます。",
      "unlimited": "無制限",
      "usage": "キャッシュ使用量",
      "usedUnlimited": "使用量 {used}（無制限）",
      "usedLimit": "{used} / {max} 使用",
      "max": "最大キャッシュサイズ",
      "eviction": "上限に達すると、最も長く使用されていないファイルが削除されます。",
      "fileOne": "{count} ファイル",
      "fileOther": "{count} ファイル",
      "fileZero": "{count} ファイル",
      "fileTwo": "{count} ファイル",
      "fileFew": "{count} ファイル",
      "fileMany": "{count} ファイル",
    },
    'ko': {
      "settings": "캐시 설정",
      "clearTitle": "캐시 지우기",
      "clearConfirm": "캐시된 파일을 모두 삭제하시겠습니까? 필요할 때 다시 다운로드됩니다.",
      "unlimited": "무제한",
      "usage": "캐시 사용량",
      "usedUnlimited": "{used} 사용 (무제한)",
      "usedLimit": "{used} / {max} 사용",
      "max": "최대 캐시 크기",
      "eviction": "한도에 도달하면 가장 오랫동안 사용하지 않은 파일이 삭제됩니다.",
      "fileOne": "파일 {count}개",
      "fileOther": "파일 {count}개",
      "fileZero": "파일 {count}개",
      "fileTwo": "파일 {count}개",
      "fileFew": "파일 {count}개",
      "fileMany": "파일 {count}개",
    },
    'ar': {
      "settings": "إعدادات ذاكرة التخزين المؤقت",
      "clearTitle": "مسح ذاكرة التخزين المؤقت",
      "clearConfirm":
          "هل تريد إزالة كل الملفات المخزنة مؤقتًا؟ ستُنزّل مجددًا عند الحاجة.",
      "unlimited": "غير محدود",
      "usage": "استخدام ذاكرة التخزين المؤقت",
      "usedUnlimited": "المستخدم {used} (غير محدود)",
      "usedLimit": "المستخدم {used} / {max}",
      "max": "الحد الأقصى لحجم ذاكرة التخزين المؤقت",
      "eviction": "عند بلوغ الحد، تُزال الملفات التي لم تُستخدم منذ أطول وقت.",
      "fileOne": "ملف واحد",
      "fileOther": "{count} ملف",
      "fileZero": "لا ملفات",
      "fileTwo": "ملفان",
      "fileFew": "{count} ملفات",
      "fileMany": "{count} ملفًا",
    },
  };
}
