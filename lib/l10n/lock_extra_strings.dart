import 'package:flutter/widgets.dart';

/// App-lock messages that interpolate the device's biometric method.
class LockExtraStrings {
  LockExtraStrings(BuildContext context)
      : _v = _translations[Localizations.localeOf(context).languageCode] ??
            _translations['en']!;
  final List<String> _v;
  String biometric(String label) => switch (label) {
        'Biometric' => _v[0],
        'Fingerprint' => _v[1],
        _ => label,
      };
  String useOrPin(String label) =>
      _v[2].replaceAll('{method}', biometric(label));
  String unlockWith(String label) =>
      _v[3].replaceAll('{method}', biometric(label));
  String alternative(String label) =>
      _v[4].replaceAll('{method}', biometric(label));
  String get or => _v[5];
  String get lockedButton => _v[6];
  String get minLengthError => _v[7];
  String get incorrectCurrent => _v[8];

  static const _translations = <String, List<String>>{
    'en': [
      'Biometric',
      'Fingerprint',
      'Use {method} or enter your PIN/password',
      'Unlock with {method}',
      'Use {method} as an alternative to your PIN/password',
      'or',
      'Too many attempts',
      'PIN/password must be at least 4 characters',
      'Current PIN/password is incorrect'
    ],
    'de': [
      'Biometrie',
      'Fingerabdruck',
      '{method} verwenden oder PIN/Passwort eingeben',
      'Mit {method} entsperren',
      '{method} als Alternative zur PIN/zum Passwort verwenden',
      'oder',
      'Zu viele Versuche',
      'PIN/Passwort muss mindestens 4 Zeichen lang sein',
      'Aktuelle PIN/aktuelles Passwort ist falsch'
    ],
    'fr': [
      'Biométrie',
      'Empreinte digitale',
      'Utilisez {method} ou saisissez votre code PIN/mot de passe',
      'Déverrouiller avec {method}',
      'Utiliser {method} à la place du code PIN/mot de passe',
      'ou',
      'Trop de tentatives',
      'Le code PIN/mot de passe doit comporter au moins 4 caractères',
      'Le code PIN/mot de passe actuel est incorrect'
    ],
    'es': [
      'Biometría',
      'Huella digital',
      'Usa {method} o introduce tu PIN/contraseña',
      'Desbloquear con {method}',
      'Usar {method} como alternativa al PIN/contraseña',
      'o',
      'Demasiados intentos',
      'El PIN/contraseña debe tener al menos 4 caracteres',
      'El PIN/contraseña actual es incorrecto'
    ],
    'pt': [
      'Biometria',
      'Impressão digital',
      'Use {method} ou digite seu PIN/senha',
      'Desbloquear com {method}',
      'Usar {method} como alternativa ao PIN/senha',
      'ou',
      'Muitas tentativas',
      'O PIN/senha deve ter pelo menos 4 caracteres',
      'O PIN/senha atual está incorreto'
    ],
    'ar': [
      'القياسات الحيوية',
      'بصمة الإصبع',
      'استخدم {method} أو أدخل رمز PIN أو كلمة المرور',
      'فتح باستخدام {method}',
      'استخدام {method} بدلاً من رمز PIN أو كلمة المرور',
      'أو',
      'محاولات كثيرة جداً',
      'يجب أن يتكون رمز PIN أو كلمة المرور من 4 أحرف على الأقل',
      'رمز PIN أو كلمة المرور الحالية غير صحيحة'
    ],
    'ja': [
      '生体認証',
      '指紋認証',
      '{method}を使用するか、PINまたはパスワードを入力してください',
      '{method}でロック解除',
      'PINまたはパスワードの代わりに{method}を使用',
      'または',
      '試行回数が多すぎます',
      'PINまたはパスワードは4文字以上にしてください',
      '現在のPINまたはパスワードが正しくありません'
    ],
    'ko': [
      '생체 인증',
      '지문',
      '{method}을 사용하거나 PIN/비밀번호를 입력하세요',
      '{method}으로 잠금 해제',
      'PIN/비밀번호 대신 {method} 사용',
      '또는',
      '시도 횟수 초과',
      'PIN/비밀번호는 4자 이상이어야 합니다',
      '현재 PIN/비밀번호가 올바르지 않습니다'
    ],
    'zh': [
      '生物识别',
      '指纹',
      '使用{method}或输入 PIN/密码',
      '使用{method}解锁',
      '使用{method}代替 PIN/密码',
      '或',
      '尝试次数过多',
      'PIN/密码至少需要 4 个字符',
      '当前 PIN/密码不正确'
    ],
  };
}
