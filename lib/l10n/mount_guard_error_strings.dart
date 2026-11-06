/// Translates exact app-authored mount validation errors only.
/// Unknown operating-system messages retain their original text.
String? localizedMountGuardErrorForLanguage(String language, Object error) {
  final String message;
  if (error is StateError) {
    message = error.message;
  } else if (error is ArgumentError) {
    if (error.message is! String) return null;
    message = error.message as String;
  } else if (error is UnsupportedError) {
    message = error.message ?? '';
  } else if (error is String) {
    message = error;
  } else {
    return null;
  }
  var index = _source.indexOf(message);
  if (index < 0 && error is String) {
    // Some legacy mount entries store the standard exception wrapper.
    for (final prefix in [
      'Bad state: ',
      'Invalid argument(s): ',
      'Unsupported operation: ',
    ]) {
      if (message.startsWith(prefix)) {
        index = _source.indexOf(message.substring(prefix.length));
        if (index >= 0) break;
      }
    }
  }
  if (index < 0) return null;
  return (_translations[language] ?? _translations['en']!)[index];
}

const _source = <String>[
  "Cannot mount while mounts are being shut down",
  "FUSE-T requires non-commercial-use acknowledgement",
  "Cloud client required",
  "rclone NFS is currently available on macOS only",
  "An rclone remote such as work:documents is required",
  "Cannot remove a mount while its state is changing",
  "Cannot remove a mount that is still active",
];
const _translations = <String, List<String>>{
  "en": [
    "Cannot mount while mounts are being shut down",
    "FUSE-T requires non-commercial-use acknowledgement",
    "Cloud client required",
    "rclone NFS is currently available on macOS only",
    "An rclone remote such as work:documents is required",
    "Cannot remove a mount while its state is changing",
    "Cannot remove a mount that is still active",
  ],
  "de": [
    "Während Einbindungen beendet werden, kann keine neue Einbindung erstellt werden.",
    "Für FUSE-T muss die nichtkommerzielle Nutzung bestätigt werden.",
    "Eine Verbindung zu einem Cloud-Anbieter ist erforderlich.",
    "rclone NFS ist derzeit nur unter macOS verfügbar.",
    "Ein rclone-Ziel wie work:documents ist erforderlich.",
    "Eine Einbindung kann während eines Zustandswechsels nicht entfernt werden.",
    "Eine noch aktive Einbindung kann nicht entfernt werden.",
  ],
  "fr": [
    "Impossible de monter pendant l’arrêt des montages.",
    "L’utilisation non commerciale de FUSE-T doit être confirmée.",
    "Une connexion à un fournisseur cloud est requise.",
    "rclone NFS est actuellement disponible uniquement sur macOS.",
    "Une destination rclone telle que work:documents est requise.",
    "Impossible de supprimer un montage pendant un changement d’état.",
    "Impossible de supprimer un montage encore actif.",
  ],
  "es": [
    "No se puede montar mientras se están cerrando los montajes.",
    "Se debe confirmar el uso no comercial de FUSE-T.",
    "Se requiere una conexión a un proveedor de nube.",
    "rclone NFS solo está disponible actualmente en macOS.",
    "Se requiere un remoto de rclone como work:documents.",
    "No se puede eliminar un montaje mientras cambia de estado.",
    "No se puede eliminar un montaje que sigue activo.",
  ],
  "pt": [
    "Não é possível montar enquanto as montagens estão a ser encerradas.",
    "É necessário confirmar a utilização não comercial do FUSE-T.",
    "É necessária uma ligação a um fornecedor de nuvem.",
    "O rclone NFS está atualmente disponível apenas no macOS.",
    "É necessário um remoto rclone como work:documents.",
    "Não é possível remover uma montagem enquanto muda de estado.",
    "Não é possível remover uma montagem ainda ativa.",
  ],
  "zh": [
    "正在关闭挂载，无法创建新挂载。",
    "必须确认 FUSE-T 仅用于非商业用途。",
    "需要连接云存储提供商。",
    "rclone NFS 目前仅适用于 macOS。",
    "需要指定 work:documents 这样的 rclone 远程位置。",
    "挂载状态正在变化，无法移除。",
    "无法移除仍处于活动状态的挂载。",
  ],
  "ja": [
    "マウントの終了処理中は新たにマウントできません。",
    "FUSE-T の非商用利用の確認が必要です。",
    "クラウドプロバイダーへの接続が必要です。",
    "rclone NFS は現在 macOS でのみ利用できます。",
    "work:documents のような rclone リモートを指定してください。",
    "状態の変更中はマウントを削除できません。",
    "まだ有効なマウントは削除できません。",
  ],
  "ko": [
    "마운트를 종료하는 동안 새로 마운트할 수 없습니다.",
    "FUSE-T의 비상업적 사용을 확인해야 합니다.",
    "클라우드 공급자 연결이 필요합니다.",
    "rclone NFS는 현재 macOS에서만 사용할 수 있습니다.",
    "work:documents와 같은 rclone 원격 위치가 필요합니다.",
    "상태가 변경되는 동안 마운트를 제거할 수 없습니다.",
    "아직 활성 상태인 마운트는 제거할 수 없습니다.",
  ],
  "ar": [
    "لا يمكن التثبيت أثناء إيقاف التثبيتات.",
    "يجب تأكيد الاستخدام غير التجاري لـ FUSE-T.",
    "يلزم الاتصال بمزوّد تخزين سحابي.",
    "يتوفر rclone NFS حالياً على macOS فقط.",
    "يلزم تحديد وجهة rclone مثل work:documents.",
    "لا يمكن إزالة تثبيت أثناء تغيّر حالته.",
    "لا يمكن إزالة تثبيت ما زال نشطاً.",
  ],
};
