import 'package:flutter/widgets.dart';

class ScreenTerminalStrings {
  const ScreenTerminalStrings(this.language);
  final String language;

  String text(String english) {
    final index = _languages.indexOf(language);
    final values = _values[english];
    return index < 0 || values == null ? english : values[index];
  }

  static const _languages = ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'];
  static const _values = <String, List<String>>{
    'Create new screen': [
      'Neue screen-Sitzung erstellen',
      'Créer une session screen',
      'Crear una sesión screen',
      'Criar uma sessão screen',
      '新建 screen 会话',
      'screen セッションを新規作成',
      '새 screen 세션 만들기',
      'إنشاء جلسة screen جديدة',
    ],
    'Attach existing screen': [
      'Bestehende screen-Sitzung öffnen',
      'Rejoindre une session screen',
      'Conectar a una sesión screen',
      'Conectar a uma sessão screen',
      '连接现有 screen 会话',
      '既存の screen セッションに接続',
      '기존 screen 세션에 연결',
      'الاتصال بجلسة screen موجودة',
    ],
    'screen session name': [
      'Name der screen-Sitzung',
      'Nom de la session screen',
      'Nombre de la sesión screen',
      'Nome da sessão screen',
      'screen 会话名称',
      'screen セッション名',
      'screen 세션 이름',
      'اسم جلسة screen',
    ],
    'screen session name or PID.name': [
      'screen-Sitzungsname oder PID.name',
      'Nom de session screen ou PID.name',
      'Nombre de sesión screen o PID.name',
      'Nome da sessão screen ou PID.name',
      'screen 会话名称或 PID.name',
      'screen セッション名または PID.name',
      'screen 세션 이름 또는 PID.name',
      'اسم جلسة screen أو PID.name',
    ],
    'Detach from screen': [
      'Von screen lösen',
      'Se détacher de screen',
      'Desconectarse de screen',
      'Desanexar do screen',
      '分离 screen 会话',
      'screen からデタッチ',
      'screen에서 분리',
      'الانفصال عن screen',
    ],
    'screen must be installed on the server. New sessions keep running when you disconnect.':
        [
          'screen muss auf dem Server installiert sein. Neue Sitzungen laufen nach dem Trennen weiter.',
          'screen doit être installé sur le serveur. Les nouvelles sessions continuent après la déconnexion.',
          'screen debe estar instalado en el servidor. Las sesiones nuevas siguen ejecutándose al desconectarse.',
          'O screen deve estar instalado no servidor. As novas sessões continuam após desconectar.',
          '服务器必须安装 screen。断开连接后，新建的会话会继续运行。',
          'サーバーに screen のインストールが必要です。新規セッションは切断後も実行され続けます。',
          '서버에 screen이 설치되어 있어야 합니다. 새 세션은 연결을 끊어도 계속 실행됩니다.',
          'يجب تثبيت screen على الخادم. تستمر الجلسات الجديدة في العمل بعد قطع الاتصال.',
        ],
    'Attach uses an exact name or full PID.name from screen -ls. Other displays stay connected.':
        [
          'Zum Öffnen den genauen Namen oder die vollständige PID.name aus screen -ls verwenden. Andere Terminals bleiben verbunden.',
          'Utilisez le nom exact ou le PID.name complet indiqué par screen -ls. Les autres terminaux restent connectés.',
          'Use el nombre exacto o el PID.name completo de screen -ls. Los demás terminales siguen conectados.',
          'Use o nome exato ou o PID.name completo de screen -ls. Os outros terminais permanecem conectados.',
          '使用准确的名称或 screen -ls 显示的完整 PID.name 连接。其他终端保持连接。',
          '正確な名前または screen -ls の完全な PID.name で接続します。他の端末の接続は維持されます。',
          '정확한 이름이나 screen -ls의 전체 PID.name으로 연결합니다. 다른 터미널은 연결을 유지합니다.',
          'استخدم الاسم المطابق أو PID.name الكامل من screen -ls. تبقى الطرفيات الأخرى متصلة.',
        ],
    'Use a session name (1–64 ASCII letters, digits, _ or -), or a full PID.name.':
        [
          'Sitzungsname (1–64 ASCII-Buchstaben, Ziffern, _ oder -) oder vollständige PID.name eingeben.',
          'Utilisez un nom (1 à 64 lettres ASCII, chiffres, _ ou -) ou un PID.name complet.',
          'Use un nombre (1–64 letras ASCII, dígitos, _ o -) o un PID.name completo.',
          'Use um nome (1–64 letras ASCII, dígitos, _ ou -) ou um PID.name completo.',
          '请输入会话名称（1–64 个 ASCII 字母、数字、_ 或 -），或完整的 PID.name。',
          'セッション名（1～64 文字の ASCII 英数字、_、-）または完全な PID.name を入力してください。',
          '세션 이름(ASCII 영문자, 숫자, _, -로 1~64자)이나 전체 PID.name을 입력하세요.',
          'استخدم اسم جلسة (1–64 حرف ASCII أو رقمًا أو _ أو -) أو PID.name الكامل.',
        ],
  };
}

extension ScreenTerminalContextStrings on BuildContext {
  String screenTr(String english) => ScreenTerminalStrings(
    Localizations.maybeLocaleOf(this)?.languageCode ?? 'en',
  ).text(english);
}
