/// Host labels for the Zotero entry point and credential-store diagnostics.
abstract final class OfficeZoteroStrings {
  static String? lookup(String language, String english) =>
      _translations[language]?[english];

  static const _translations = <String, Map<String, String>>{
    'de': {
      'References': 'Referenzen',
      'Could not open Zotero. Please try again.':
          'Zotero konnte nicht geöffnet werden. Bitte erneut versuchen.',
      'Could not read the saved Zotero API key.':
          'Der gespeicherte Zotero-API-Schlüssel konnte nicht gelesen werden.',
    },
    'fr': {
      'References': 'Références',
      'Could not open Zotero. Please try again.':
          'Impossible d’ouvrir Zotero. Veuillez réessayer.',
      'Could not read the saved Zotero API key.':
          'Impossible de lire la clé API Zotero enregistrée.',
    },
    'es': {
      'References': 'Referencias',
      'Could not open Zotero. Please try again.':
          'No se pudo abrir Zotero. Inténtalo de nuevo.',
      'Could not read the saved Zotero API key.':
          'No se pudo leer la clave API de Zotero guardada.',
    },
    'pt': {
      'References': 'Referências',
      'Could not open Zotero. Please try again.':
          'Não foi possível abrir o Zotero. Tente novamente.',
      'Could not read the saved Zotero API key.':
          'Não foi possível ler a chave API do Zotero guardada.',
    },
    'ja': {
      'References': '参考資料',
      'Could not open Zotero. Please try again.':
          'Zoteroを開けませんでした。もう一度お試しください。',
      'Could not read the saved Zotero API key.':
          '保存されたZotero APIキーを読み取れませんでした。',
    },
    'ko': {
      'References': '참조',
      'Could not open Zotero. Please try again.': 'Zotero를 열 수 없습니다. 다시 시도하세요.',
      'Could not read the saved Zotero API key.':
          '저장된 Zotero API 키를 읽을 수 없습니다.',
    },
    'zh': {
      'References': '引用',
      'Could not open Zotero. Please try again.': '无法打开 Zotero。请重试。',
      'Could not read the saved Zotero API key.': '无法读取已保存的 Zotero API 密钥。',
    },
    'ar': {
      'References': 'المراجع',
      'Could not open Zotero. Please try again.':
          'تعذّر فتح Zotero. يُرجى المحاولة مرة أخرى.',
      'Could not read the saved Zotero API key.':
          'تعذّرت قراءة مفتاح Zotero API المحفوظ.',
    },
  };
}
