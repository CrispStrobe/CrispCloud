import 'package:flutter/widgets.dart';

import '../services/synchronized_browsing_service.dart';

class SynchronizedBrowsingStrings {
  SynchronizedBrowsingStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;

  String text(String key) =>
      _messages[language]?[key] ?? _messages['en']![key] ?? key;

  String failure(BrowsingLinkIssue issue, String? path) =>
      text(issue.name).replaceAll('{path}', path ?? '');

  static const _messages = {
    'en': {
      'start': 'Start synchronized browsing',
      'stop': 'Stop synchronized browsing',
      'active': 'Synchronized browsing',
      'dismiss': 'Dismiss',
      'unavailable':
          'Open an available folder in both panes before linking them.',
      'locked':
          'Synchronized browsing stopped. Use unlocked tabs to link folders.',
      'outsideRoots':
          'Synchronized browsing stopped outside the linked roots: {path}',
      'missingFolder': 'Synchronized browsing stopped. The matching folder is missing: {path}',
      'changed': 'Synchronized browsing stopped because a tab, source or pending navigation changed.',
      'failed': 'Synchronized browsing stopped. The matching folder could not be opened: {path}',
    },
    'de': {
      'start': 'Synchrones Browsen starten',
      'stop': 'Synchrones Browsen beenden',
      'active': 'Synchrones Browsen',
      'dismiss': 'Schließen',
      'unavailable': 'Öffnen Sie in beiden Bereichen einen verfügbaren Ordner.',
      'locked':
          'Synchrones Browsen beendet. Verwenden Sie nicht gesperrte Tabs.',
      'outsideRoots':
          'Synchrones Browsen außerhalb der verbundenen Ordner beendet: {path}',
      'missingFolder':
          'Synchrones Browsen beendet. Der passende Ordner fehlt: {path}',
      'changed': 'Synchrones Browsen beendet, da sich ein Tab, die Quelle oder die Navigation geändert hat.',
      'failed': 'Synchrones Browsen beendet. Der passende Ordner konnte nicht geöffnet werden: {path}',
    },
    'fr': {
      'start': 'Démarrer la navigation synchronisée',
      'stop': 'Arrêter la navigation synchronisée',
      'active': 'Navigation synchronisée',
      'dismiss': 'Fermer',
      'unavailable': 'Ouvrez un dossier disponible dans chaque panneau.',
      'locked': 'Navigation synchronisée arrêtée. Utilisez des onglets déverrouillés.',
      'outsideRoots':
          'Navigation synchronisée arrêtée hors des dossiers liés : {path}',
      'missingFolder': 'Navigation synchronisée arrêtée. Dossier correspondant absent : {path}',
      'changed': 'Navigation synchronisée arrêtée après un changement d’onglet, de source ou de navigation.',
      'failed': 'Navigation synchronisée arrêtée. Impossible d’ouvrir le dossier correspondant : {path}',
    },
    'es': {
      'start': 'Iniciar navegación sincronizada',
      'stop': 'Detener navegación sincronizada',
      'active': 'Navegación sincronizada',
      'dismiss': 'Cerrar',
      'unavailable': 'Abre una carpeta disponible en cada panel.',
      'locked': 'Navegación sincronizada detenida. Usa pestañas desbloqueadas.',
      'outsideRoots': 'Navegación sincronizada detenida fuera de las carpetas vinculadas: {path}',
      'missingFolder': 'Navegación sincronizada detenida. Falta la carpeta correspondiente: {path}',
      'changed': 'Navegación sincronizada detenida porque cambió una pestaña, el origen o la navegación.',
      'failed': 'Navegación sincronizada detenida. No se pudo abrir la carpeta correspondiente: {path}',
    },
    'pt': {
      'start': 'Iniciar navegação sincronizada',
      'stop': 'Parar navegação sincronizada',
      'active': 'Navegação sincronizada',
      'dismiss': 'Fechar',
      'unavailable': 'Abra uma pasta disponível em cada painel.',
      'locked': 'Navegação sincronizada parada. Use separadores desbloqueados.',
      'outsideRoots':
          'Navegação sincronizada parada fora das pastas ligadas: {path}',
      'missingFolder':
          'Navegação sincronizada parada. Falta a pasta correspondente: {path}',
      'changed': 'Navegação sincronizada parada porque o separador, a origem ou a navegação mudou.',
      'failed': 'Navegação sincronizada parada. Não foi possível abrir a pasta correspondente: {path}',
    },
    'zh': {
      'start': '开始同步浏览',
      'stop': '停止同步浏览',
      'active': '同步浏览',
      'dismiss': '关闭',
      'unavailable': '请在两个窗格中分别打开可用的文件夹。',
      'locked': '同步浏览已停止。请使用未锁定的标签页。',
      'outsideRoots': '已离开关联的根目录，同步浏览已停止：{path}',
      'missingFolder': '同步浏览已停止。对应文件夹不存在：{path}',
      'changed': '标签页、存储源或导航发生变化，同步浏览已停止。',
      'failed': '同步浏览已停止。无法打开对应文件夹：{path}',
    },
    'ja': {
      'start': '同期ブラウズを開始',
      'stop': '同期ブラウズを停止',
      'active': '同期ブラウズ',
      'dismiss': '閉じる',
      'unavailable': '両方のペインで利用可能なフォルダーを開いてください。',
      'locked': '同期ブラウズを停止しました。ロックされていないタブを使用してください。',
      'outsideRoots': 'リンクしたルートの外に移動したため同期ブラウズを停止しました: {path}',
      'missingFolder': '同期ブラウズを停止しました。対応するフォルダーがありません: {path}',
      'changed': 'タブ、保存先、または移動先が変更されたため同期ブラウズを停止しました。',
      'failed': '同期ブラウズを停止しました。対応するフォルダーを開けませんでした: {path}',
    },
    'ko': {
      'start': '동기 탐색 시작',
      'stop': '동기 탐색 중지',
      'active': '동기 탐색',
      'dismiss': '닫기',
      'unavailable': '두 패널에서 사용 가능한 폴더를 여세요.',
      'locked': '동기 탐색이 중지되었습니다. 잠금 해제된 탭을 사용하세요.',
      'outsideRoots': '연결된 루트 밖으로 이동하여 동기 탐색이 중지되었습니다: {path}',
      'missingFolder': '동기 탐색이 중지되었습니다. 해당 폴더가 없습니다: {path}',
      'changed': '탭, 저장소 또는 탐색 위치가 변경되어 동기 탐색이 중지되었습니다.',
      'failed': '동기 탐색이 중지되었습니다. 해당 폴더를 열 수 없습니다: {path}',
    },
    'ar': {
      'start': 'بدء التصفح المتزامن',
      'stop': 'إيقاف التصفح المتزامن',
      'active': 'التصفح المتزامن',
      'dismiss': 'إغلاق',
      'unavailable': 'افتح مجلدًا متاحًا في كلتا اللوحتين قبل ربطهما.',
      'locked': 'توقف التصفح المتزامن. استخدم علامات تبويب غير مقفلة.',
      'outsideRoots': 'توقف التصفح المتزامن خارج المجلدات المرتبطة: {path}',
      'missingFolder': 'توقف التصفح المتزامن. المجلد المقابل غير موجود: {path}',
      'changed':
          'توقف التصفح المتزامن بسبب تغيير علامة التبويب أو المصدر أو التنقل.',
      'failed': 'توقف التصفح المتزامن. تعذر فتح المجلد المقابل: {path}',
    },
  };
}
