/// Recovery actions use the same supported locales as the Office chrome.
class OfficeRecoveryStrings {
  const OfficeRecoveryStrings._();

  static String? lookup(String language, String english) =>
      _translations[language]?[english];

  static const _translations = <String, Map<String, String>>{
    'de': {
      'Save a copy': 'Kopie speichern',
      'Export original': 'Original exportieren',
      'Copy saved. The original is unchanged.':
          'Kopie gespeichert. Das Original ist unverändert.',
      'Copy download started. The original is unchanged.':
          'Download der Kopie gestartet. Das Original ist unverändert.',
      'Could not save a copy': 'Kopie konnte nicht gespeichert werden',
    },
    'fr': {
      'Save a copy': 'Enregistrer une copie',
      'Export original': 'Exporter l’original',
      'Copy saved. The original is unchanged.':
          'Copie enregistrée. L’original reste inchangé.',
      'Copy download started. The original is unchanged.':
          'Téléchargement de la copie lancé. L’original reste inchangé.',
      'Could not save a copy': 'Impossible d’enregistrer une copie',
    },
    'es': {
      'Save a copy': 'Guardar una copia',
      'Export original': 'Exportar original',
      'Copy saved. The original is unchanged.':
          'Copia guardada. El original no ha cambiado.',
      'Copy download started. The original is unchanged.':
          'Descarga de la copia iniciada. El original no ha cambiado.',
      'Could not save a copy': 'No se pudo guardar una copia',
    },
    'pt': {
      'Save a copy': 'Salvar uma cópia',
      'Export original': 'Exportar original',
      'Copy saved. The original is unchanged.':
          'Cópia salva. O original permanece inalterado.',
      'Copy download started. The original is unchanged.':
          'Download da cópia iniciado. O original permanece inalterado.',
      'Could not save a copy': 'Não foi possível salvar uma cópia',
    },
    'ja': {
      'Save a copy': 'コピーを保存',
      'Export original': '元のファイルをエクスポート',
      'Copy saved. The original is unchanged.':
          'コピーを保存しました。元のファイルは変更されていません。',
      'Copy download started. The original is unchanged.':
          'コピーのダウンロードを開始しました。元のファイルは変更されていません。',
      'Could not save a copy': 'コピーを保存できませんでした',
    },
    'ko': {
      'Save a copy': '사본 저장',
      'Export original': '원본 내보내기',
      'Copy saved. The original is unchanged.':
          '사본을 저장했습니다. 원본은 변경되지 않았습니다.',
      'Copy download started. The original is unchanged.':
          '사본 다운로드를 시작했습니다. 원본은 변경되지 않았습니다.',
      'Could not save a copy': '사본을 저장할 수 없습니다',
    },
    'zh': {
      'Save a copy': '保存副本',
      'Export original': '导出原始文件',
      'Copy saved. The original is unchanged.': '副本已保存。原始文件未更改。',
      'Copy download started. The original is unchanged.':
          '已开始下载副本。原始文件未更改。',
      'Could not save a copy': '无法保存副本',
    },
    'ar': {
      'Save a copy': 'حفظ نسخة',
      'Export original': 'تصدير الأصل',
      'Copy saved. The original is unchanged.':
          'تم حفظ النسخة. لم يتغير الملف الأصلي.',
      'Copy download started. The original is unchanged.':
          'بدأ تنزيل النسخة. لم يتغير الملف الأصلي.',
      'Could not save a copy': 'تعذر حفظ نسخة',
    },
  };
}
