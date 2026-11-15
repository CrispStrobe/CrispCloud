import 'package:flutter/widgets.dart';

extension TerminalBroadcastStrings on BuildContext {
  String terminalBroadcastTr(String english) {
    final language = Localizations.maybeLocaleOf(this)?.languageCode ?? 'en';
    final index = _languages.indexOf(language);
    return index < 0 ? english : _values[english]?[index] ?? english;
  }
}

const _languages = ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'];
const _values = <String, List<String>>{
  'Stop': ['Stopp', 'Arrêter', 'Detener', 'Parar', '停止', '停止', '중지', 'إيقاف'],
  'Broadcast input': [
    'Eingabe an mehrere Terminals',
    'Diffuser la saisie',
    'Difundir entrada',
    'Transmitir entrada',
    '广播输入',
    '入力を一斉送信',
    '입력 동시 전송',
    'بث الإدخال',
  ],
  'Start broadcasting': [
    'Gemeinsame Eingabe starten',
    'Commencer la diffusion',
    'Iniciar difusión',
    'Iniciar transmissão',
    '开始广播',
    '一斉送信を開始',
    '동시 전송 시작',
    'بدء البث',
  ],
  'Stop broadcast': [
    'Gemeinsame Eingabe beenden',
    'Arrêter la diffusion',
    'Detener difusión',
    'Parar transmissão',
    '停止广播',
    '一斉送信を停止',
    '동시 전송 중지',
    'إيقاف البث',
  ],
  'Broadcasting to {count} terminals': [
    'Eingabe an {count} Terminals',
    'Diffusion vers {count} terminaux',
    'Difundiendo a {count} terminales',
    'A transmitir para {count} terminais',
    '正在向 {count} 个终端广播',
    '{count} 個のターミナルに一斉送信中',
    '{count}개 터미널에 동시 전송 중',
    'البث إلى {count} طرفيات',
  ],
  'Select at least two connected terminals.': [
    'Wählen Sie mindestens zwei verbundene Terminals aus.',
    'Sélectionnez au moins deux terminaux connectés.',
    'Selecciona al menos dos terminales conectadas.',
    'Selecione pelo menos dois terminais ligados.',
    '请至少选择两个已连接的终端。',
    '接続済みのターミナルを2つ以上選択してください。',
    '연결된 터미널을 두 개 이상 선택하세요.',
    'اختر طرفيتين متصلتين على الأقل.',
  ],
  'Typed keys and pasted text will be sent to every selected terminal.': [
    'Gedrückte Tasten und eingefügter Text werden an jedes ausgewählte Terminal gesendet.',
    'Les touches saisies et le texte collé seront envoyés à chaque terminal sélectionné.',
    'Las teclas y el texto pegado se enviarán a todas las terminales seleccionadas.',
    'As teclas e o texto colado serão enviados para todos os terminais selecionados.',
    '键入的按键和粘贴的文本将发送到每个选中的终端。',
    '入力したキーと貼り付けたテキストは、選択したすべてのターミナルに送信されます。',
    '입력한 키와 붙여넣은 텍스트가 선택한 모든 터미널로 전송됩니다.',
    'ستُرسل المفاتيح المكتوبة والنصوص الملصقة إلى كل طرفية محددة.',
  ],
  'Connection changed': [
    'Verbindung geändert',
    'Connexion modifiée',
    'Conexión modificada',
    'Ligação alterada',
    '连接已更改',
    '接続が変更されました',
    '연결 변경됨',
    'تغير الاتصال',
  ],
  'Connections changed. Choose the broadcast group again.': [
    'Verbindungen wurden geändert. Wählen Sie die Gruppe für gemeinsame Eingaben erneut aus.',
    'Les connexions ont changé. Choisissez à nouveau le groupe de diffusion.',
    'Las conexiones cambiaron. Vuelve a elegir el grupo de difusión.',
    'As ligações mudaram. Escolha novamente o grupo de transmissão.',
    '连接已更改。请重新选择广播组。',
    '接続が変更されました。一斉送信のグループを選び直してください。',
    '연결이 변경되었습니다. 동시 전송 그룹을 다시 선택하세요.',
    'تغيرت الاتصالات. اختر مجموعة البث مجددًا.',
  ],
  'Broadcast stopped because a connection changed.': [
    'Die gemeinsame Eingabe wurde wegen einer geänderten Verbindung beendet.',
    'La diffusion s’est arrêtée car une connexion a changé.',
    'La difusión se detuvo porque cambió una conexión.',
    'A transmissão parou porque uma ligação mudou.',
    '由于连接发生变化，广播已停止。',
    '接続が変更されたため一斉送信を停止しました。',
    '연결이 변경되어 동시 전송을 중지했습니다.',
    'توقف البث بسبب تغير اتصال.',
  ],
  'Broadcast stopped because the input was too large.': [
    'Die gemeinsame Eingabe wurde beendet, weil die Eingabe zu groß war.',
    'La diffusion s’est arrêtée car la saisie était trop volumineuse.',
    'La difusión se detuvo porque la entrada era demasiado grande.',
    'A transmissão parou porque a entrada era demasiado grande.',
    '由于输入过大，广播已停止。',
    '入力が大きすぎるため一斉送信を停止しました。',
    '입력이 너무 커서 동시 전송을 중지했습니다.',
    'توقف البث لأن الإدخال كان كبيرًا جدًا.',
  ],
  'Broadcast stopped because input could not be delivered.': [
    'Die gemeinsame Eingabe wurde beendet, weil die Eingabe nicht zugestellt werden konnte.',
    'La diffusion s’est arrêtée car la saisie n’a pas pu être transmise.',
    'La difusión se detuvo porque no se pudo enviar la entrada.',
    'A transmissão parou porque não foi possível enviar a entrada.',
    '由于无法发送输入，广播已停止。',
    '入力を送信できなかったため一斉送信を停止しました。',
    '입력을 전달할 수 없어 동시 전송을 중지했습니다.',
    'توقف البث لتعذر تسليم الإدخال.',
  ],
};
