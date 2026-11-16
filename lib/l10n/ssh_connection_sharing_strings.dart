import 'package:flutter/widgets.dart';

extension SshConnectionSharingStrings on BuildContext {
  String sshSharingTr(String english) {
    final language = Localizations.maybeLocaleOf(this)?.languageCode ?? 'en';
    final index = _languages.indexOf(language);
    return index < 0 ? english : _values[english]?[index] ?? english;
  }
}

const _languages = ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'];
const _values = <String, List<String>>{
  'New SSH shell': [
    'Neue SSH-Shell',
    'Nouveau shell SSH',
    'Nuevo shell SSH',
    'Novo shell SSH',
    '新建 SSH Shell',
    '新しい SSH シェル',
    '새 SSH 셸',
    'صدفة SSH جديدة',
  ],
  'Split SSH side by side': [
    'SSH nebeneinander teilen',
    'Diviser SSH côte à côte',
    'Dividir SSH lado a lado',
    'Dividir SSH lado a lado',
    'SSH 左右分屏',
    'SSH を左右に分割',
    'SSH 좌우 분할',
    'تقسيم SSH جنبًا إلى جنب',
  ],
  'Split SSH top and bottom': [
    'SSH übereinander teilen',
    'Diviser SSH de haut en bas',
    'Dividir SSH arriba y abajo',
    'Dividir SSH em cima e em baixo',
    'SSH 上下分屏',
    'SSH を上下に分割',
    'SSH 위아래 분할',
    'تقسيم SSH أعلى وأسفل',
  ],
  'Shared SSH connection': [
    'Gemeinsam genutzte SSH-Verbindung',
    'Connexion SSH partagée',
    'Conexión SSH compartida',
    'Ligação SSH partilhada',
    '共享 SSH 连接',
    '共有 SSH 接続',
    '공유 SSH 연결',
    'اتصال SSH مشترك',
  ],
  'This SSH connection is shared by {count} terminals. Port forwards and permitted agent access stay active until the last terminal closes.':
      [
        '{count} Terminals nutzen diese SSH-Verbindung gemeinsam. Portweiterleitungen und erlaubter Agentenzugriff bleiben bis zum Schließen des letzten Terminals aktiv.',
        '{count} terminaux partagent cette connexion SSH. Les redirections de ports et l’accès autorisé à l’agent restent actifs jusqu’à la fermeture du dernier terminal.',
        '{count} terminales comparten esta conexión SSH. Los reenvíos de puertos y el acceso autorizado al agente siguen activos hasta cerrar el último terminal.',
        '{count} terminais partilham esta ligação SSH. Os encaminhamentos de portas e o acesso autorizado ao agente continuam ativos até fechar o último terminal.',
        '{count} 个终端共享此 SSH 连接。端口转发和已授权的代理访问会保持有效，直到最后一个终端关闭。',
        '{count} 個のターミナルがこの SSH 接続を共有しています。最後のターミナルを閉じるまで、ポート転送と許可されたエージェントへのアクセスは有効なままです。',
        '{count}개 터미널이 이 SSH 연결을 공유합니다. 마지막 터미널을 닫을 때까지 포트 전달과 허용된 에이전트 접근이 유지됩니다.',
        'تشترك {count} طرفيات في اتصال SSH هذا. تظل عمليات إعادة توجيه المنافذ والوصول المسموح إلى الوكيل نشطة حتى إغلاق آخر طرفية.',
      ],
  'Closing releases this terminal. Other terminals keep the SSH connection, port forwards and permitted agent access until the last terminal closes.':
      [
        'Beim Schließen wird dieses Terminal freigegeben. Andere Terminals halten die SSH-Verbindung, Portweiterleitungen und den erlaubten Agentenzugriff bis zum Schließen des letzten Terminals offen.',
        'La fermeture libère ce terminal. Les autres terminaux conservent la connexion SSH, les redirections de ports et l’accès autorisé à l’agent jusqu’à la fermeture du dernier terminal.',
        'Al cerrar se libera este terminal. Los demás terminales mantienen la conexión SSH, los reenvíos de puertos y el acceso autorizado al agente hasta cerrar el último terminal.',
        'Fechar liberta este terminal. Os restantes terminais mantêm a ligação SSH, os encaminhamentos de portas e o acesso autorizado ao agente até fechar o último terminal.',
        '关闭会释放此终端。其他终端会保留 SSH 连接、端口转发和已授权的代理访问，直到最后一个终端关闭。',
        '閉じるとこのターミナルが解放されます。最後のターミナルを閉じるまで、他のターミナルが SSH 接続、ポート転送、許可されたエージェントへのアクセスを維持します。',
        '닫으면 이 터미널이 해제됩니다. 마지막 터미널을 닫을 때까지 다른 터미널이 SSH 연결, 포트 전달 및 허용된 에이전트 접근을 유지합니다.',
        'يحرر الإغلاق هذه الطرفية. تحتفظ الطرفيات الأخرى باتصال SSH وإعادة توجيه المنافذ والوصول المسموح إلى الوكيل حتى إغلاق آخر طرفية.',
      ],
};
