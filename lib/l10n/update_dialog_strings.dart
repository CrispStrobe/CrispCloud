import 'package:flutter/widgets.dart';

/// Text used by the update dialog.
class UpdateDialogStrings {
  UpdateDialogStrings(BuildContext context)
      : _language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  @visibleForTesting
  UpdateDialogStrings.forLanguage(this._language);
  final String _language;
  String text(String english) => _translations[_language]?[english] ?? english;
  String available(String version) =>
      text('Update Available — {version}').replaceAll('{version}', version);
  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  "de": {
    "Check for Updates": "Nach Updates suchen",
    "Close": "Schließen",
    "Update Channel": "Update-Kanal",
    "Check automatically on startup": "Beim Start automatisch prüfen",
    "Runs a background check each time the app launches":
        "Bei jedem App-Start im Hintergrund nach Updates suchen",
    "Check Now": "Jetzt prüfen",
    "Done": "Fertig",
    "Current version": "Aktuelle Version",
    "Latest version": "Neueste Version",
    "Checking for updates…": "Suche nach Updates…",
    "GitHub API rate limit reached. Please try again later.":
        "GitHub-API-Limit erreicht. Bitte später erneut versuchen.",
    "Network error — check your internet connection and try again.":
        "Netzwerkfehler — Internetverbindung prüfen und erneut versuchen.",
    "Repository not found. Check your update configuration.":
        "Repository nicht gefunden. Update-Konfiguration prüfen.",
    "You're up to date!": "Sie sind auf dem neuesten Stand!",
    "Update Available — {version}": "Update verfügbar — {version}",
    "Release Notes": "Versionshinweise",
    "Stable": "Stabil",
    "Beta": "Beta",
    "Nightly": "Nächtlich",
    "Download Update": "Update herunterladen",
  },
  "fr": {
    "Check for Updates": "Rechercher des mises à jour",
    "Close": "Fermer",
    "Update Channel": "Canal de mise à jour",
    "Check automatically on startup": "Vérifier automatiquement au démarrage",
    "Runs a background check each time the app launches":
        "Recherche en arrière-plan à chaque lancement",
    "Check Now": "Vérifier maintenant",
    "Done": "Terminé",
    "Current version": "Version actuelle",
    "Latest version": "Dernière version",
    "Checking for updates…": "Recherche de mises à jour…",
    "GitHub API rate limit reached. Please try again later.":
        "Limite de l’API GitHub atteinte. Réessayez plus tard.",
    "Network error — check your internet connection and try again.":
        "Erreur réseau — vérifiez votre connexion Internet et réessayez.",
    "Repository not found. Check your update configuration.":
        "Dépôt introuvable. Vérifiez la configuration des mises à jour.",
    "You're up to date!": "Vous êtes à jour !",
    "Update Available — {version}": "Mise à jour disponible — {version}",
    "Release Notes": "Notes de version",
    "Stable": "Stable",
    "Beta": "Bêta",
    "Nightly": "Nocturne",
    "Download Update": "Télécharger la mise à jour",
  },
  "es": {
    "Check for Updates": "Buscar actualizaciones",
    "Close": "Cerrar",
    "Update Channel": "Canal de actualización",
    "Check automatically on startup": "Buscar automáticamente al iniciar",
    "Runs a background check each time the app launches":
        "Busca en segundo plano cada vez que se inicia la aplicación",
    "Check Now": "Buscar ahora",
    "Done": "Listo",
    "Current version": "Versión actual",
    "Latest version": "Última versión",
    "Checking for updates…": "Buscando actualizaciones…",
    "GitHub API rate limit reached. Please try again later.":
        "Se alcanzó el límite de la API de GitHub. Inténtelo más tarde.",
    "Network error — check your internet connection and try again.":
        "Error de red: compruebe su conexión a Internet e inténtelo de nuevo.",
    "Repository not found. Check your update configuration.":
        "No se encontró el repositorio. Compruebe la configuración de actualizaciones.",
    "You're up to date!": "¡Está al día!",
    "Update Available — {version}": "Actualización disponible — {version}",
    "Release Notes": "Notas de la versión",
    "Stable": "Estable",
    "Beta": "Beta",
    "Nightly": "Nocturna",
    "Download Update": "Descargar actualización",
  },
  "pt": {
    "Check for Updates": "Procurar atualizações",
    "Close": "Fechar",
    "Update Channel": "Canal de atualização",
    "Check automatically on startup": "Procurar automaticamente ao iniciar",
    "Runs a background check each time the app launches":
        "Verifica em segundo plano sempre que a aplicação inicia",
    "Check Now": "Procurar agora",
    "Done": "Concluído",
    "Current version": "Versão atual",
    "Latest version": "Versão mais recente",
    "Checking for updates…": "A procurar atualizações…",
    "GitHub API rate limit reached. Please try again later.":
        "Limite da API do GitHub atingido. Tente novamente mais tarde.",
    "Network error — check your internet connection and try again.":
        "Erro de rede — verifique a ligação à Internet e tente novamente.",
    "Repository not found. Check your update configuration.":
        "Repositório não encontrado. Verifique a configuração das atualizações.",
    "You're up to date!": "Está atualizado!",
    "Update Available — {version}": "Atualização disponível — {version}",
    "Release Notes": "Notas da versão",
    "Stable": "Estável",
    "Beta": "Beta",
    "Nightly": "Noturna",
    "Download Update": "Transferir atualização",
  },
  "zh": {
    "Check for Updates": "检查更新",
    "Close": "关闭",
    "Update Channel": "更新通道",
    "Check automatically on startup": "启动时自动检查",
    "Runs a background check each time the app launches": "每次启动应用时在后台检查更新",
    "Check Now": "立即检查",
    "Done": "完成",
    "Current version": "当前版本",
    "Latest version": "最新版本",
    "Checking for updates…": "正在检查更新…",
    "GitHub API rate limit reached. Please try again later.":
        "已达到 GitHub API 速率限制。请稍后重试。",
    "Network error — check your internet connection and try again.":
        "网络错误 — 请检查互联网连接并重试。",
    "Repository not found. Check your update configuration.": "未找到仓库。请检查更新配置。",
    "You're up to date!": "已是最新版本！",
    "Update Available — {version}": "有可用更新 — {version}",
    "Release Notes": "发行说明",
    "Stable": "稳定版",
    "Beta": "测试版",
    "Nightly": "每日构建",
    "Download Update": "下载更新",
  },
  "ja": {
    "Check for Updates": "更新を確認",
    "Close": "閉じる",
    "Update Channel": "更新チャンネル",
    "Check automatically on startup": "起動時に自動確認",
    "Runs a background check each time the app launches":
        "アプリの起動時にバックグラウンドで確認します",
    "Check Now": "今すぐ確認",
    "Done": "完了",
    "Current version": "現在のバージョン",
    "Latest version": "最新バージョン",
    "Checking for updates…": "更新を確認しています…",
    "GitHub API rate limit reached. Please try again later.":
        "GitHub API の利用制限に達しました。後でもう一度お試しください。",
    "Network error — check your internet connection and try again.":
        "ネットワークエラー — インターネット接続を確認して再試行してください。",
    "Repository not found. Check your update configuration.":
        "リポジトリが見つかりません。更新設定を確認してください。",
    "You're up to date!": "最新の状態です！",
    "Update Available — {version}": "更新があります — {version}",
    "Release Notes": "リリースノート",
    "Stable": "安定版",
    "Beta": "ベータ版",
    "Nightly": "ナイトリー",
    "Download Update": "更新をダウンロード",
  },
  "ko": {
    "Check for Updates": "업데이트 확인",
    "Close": "닫기",
    "Update Channel": "업데이트 채널",
    "Check automatically on startup": "시작 시 자동으로 확인",
    "Runs a background check each time the app launches":
        "앱을 실행할 때마다 백그라운드에서 확인합니다",
    "Check Now": "지금 확인",
    "Done": "완료",
    "Current version": "현재 버전",
    "Latest version": "최신 버전",
    "Checking for updates…": "업데이트 확인 중…",
    "GitHub API rate limit reached. Please try again later.":
        "GitHub API 요청 한도에 도달했습니다. 나중에 다시 시도하세요.",
    "Network error — check your internet connection and try again.":
        "네트워크 오류 — 인터넷 연결을 확인하고 다시 시도하세요.",
    "Repository not found. Check your update configuration.":
        "저장소를 찾을 수 없습니다. 업데이트 설정을 확인하세요.",
    "You're up to date!": "최신 버전입니다!",
    "Update Available — {version}": "업데이트 사용 가능 — {version}",
    "Release Notes": "릴리스 노트",
    "Stable": "안정 버전",
    "Beta": "베타",
    "Nightly": "나이틀리",
    "Download Update": "업데이트 다운로드",
  },
  "ar": {
    "Check for Updates": "التحقق من التحديثات",
    "Close": "إغلاق",
    "Update Channel": "قناة التحديث",
    "Check automatically on startup": "التحقق تلقائيًا عند بدء التشغيل",
    "Runs a background check each time the app launches":
        "التحقق في الخلفية عند كل تشغيل للتطبيق",
    "Check Now": "تحقق الآن",
    "Done": "تم",
    "Current version": "الإصدار الحالي",
    "Latest version": "أحدث إصدار",
    "Checking for updates…": "جارٍ التحقق من التحديثات…",
    "GitHub API rate limit reached. Please try again later.":
        "تم بلوغ حد طلبات واجهة GitHub. يُرجى المحاولة لاحقًا.",
    "Network error — check your internet connection and try again.":
        "خطأ في الشبكة — تحقق من اتصال الإنترنت وحاول مجددًا.",
    "Repository not found. Check your update configuration.":
        "لم يُعثر على المستودع. تحقق من إعدادات التحديث.",
    "You're up to date!": "أنت تستخدم أحدث إصدار!",
    "Update Available — {version}": "يتوفر تحديث — {version}",
    "Release Notes": "ملاحظات الإصدار",
    "Stable": "مستقر",
    "Beta": "تجريبي",
    "Nightly": "ليلي",
    "Download Update": "تنزيل التحديث",
  },
};
