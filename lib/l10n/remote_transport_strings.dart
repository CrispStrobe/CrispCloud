import 'package:crisp_storage/crisp_storage.dart'
    show RemoteException, RemoteLocalizedFailure;
import 'package:flutter/widgets.dart';
import 'remote_transport_extra_strings.dart';
import 'remote_validation_strings.dart';

/// Localizes structured transport failures while retaining unknown details.
String? localizedRemoteTransportError(BuildContext context, Object error) =>
    localizedRemoteTransportErrorForLanguage(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en', error);

String? localizedRemoteTransportErrorForLanguage(String language, Object error) {
  if (error is! RemoteLocalizedFailure || error.code == null) return null;
  var message = (_messages[language] ?? _messages['en']!)[error.code!.name];
  if (message == null && language == 'en') {
    return error is RemoteException ? error.message : error.toString();
  }
  message ??= remoteTransportExtraStrings[language]?[error.code!.name];
  message ??= remoteValidationStrings[language]?[error.code!.name];
  if (message == null) return null;
  final result = message.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null ? match.group(0)! : value.toString();
  });
  if (error.arguments['protocol'] case final protocol?) {
    return '$protocol: $result';
  }
  return result;
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    'accessDenied': 'Access denied. Check the connection credentials.',
    'redirects': 'Use the final server URL; redirects are not followed.',
    'httpStatus': 'Server request failed (HTTP {status}).',
    'unreachable':
        'Could not reach the server. Check its address and network access.',
    'sftpConnect':
        'Could not connect to SFTP. Check the server, username and password.',
    'smbAuth': 'SMB sign-in failed. Check your username, domain and password.',
    'smbNotFound': 'SMB share or file was not found.',
    'smbRequest':
        'SMB request failed ({type}). Check the share permissions, network and encryption setting.',
    'smbPaused': 'SMB transfer paused.'
  },
  'de': {
    'accessDenied': 'Zugriff verweigert. Prüfen Sie die Zugangsdaten.',
    'redirects':
        'Verwenden Sie die endgültige Serveradresse; Weiterleitungen werden nicht gefolgt.',
    'httpStatus': 'Serveranfrage fehlgeschlagen (HTTP {status}).',
    'unreachable':
        'Server nicht erreichbar. Prüfen Sie Adresse und Netzwerkzugriff.',
    'sftpConnect':
        'SFTP-Verbindung fehlgeschlagen. Prüfen Sie Server, Benutzername und Passwort.',
    'smbAuth':
        'SMB-Anmeldung fehlgeschlagen. Prüfen Sie Benutzername, Domäne und Passwort.',
    'smbNotFound': 'SMB-Freigabe oder Datei nicht gefunden.',
    'smbRequest':
        'SMB-Anfrage fehlgeschlagen ({type}). Prüfen Sie Freigaberechte, Netzwerk und Verschlüsselung.',
    'smbPaused': 'SMB-Übertragung pausiert.'
  },
  'fr': {
    'accessDenied': 'Accès refusé. Vérifiez les identifiants de connexion.',
    'redirects':
        'Utilisez l’adresse finale du serveur ; les redirections ne sont pas suivies.',
    'httpStatus': 'Échec de la requête serveur (HTTP {status}).',
    'unreachable': 'Serveur inaccessible. Vérifiez son adresse et le réseau.',
    'sftpConnect':
        'Connexion SFTP impossible. Vérifiez le serveur, le nom et le mot de passe.',
    'smbAuth':
        'Échec de connexion SMB. Vérifiez le nom, le domaine et le mot de passe.',
    'smbNotFound': 'Partage SMB ou fichier introuvable.',
    'smbRequest':
        'Échec de la requête SMB ({type}). Vérifiez les permissions, le réseau et le chiffrement.',
    'smbPaused': 'Transfert SMB en pause.'
  },
  'es': {
    'accessDenied': 'Acceso denegado. Comprueba las credenciales de conexión.',
    'redirects':
        'Usa la dirección final del servidor; no se siguen redirecciones.',
    'httpStatus': 'Falló la solicitud al servidor (HTTP {status}).',
    'unreachable':
        'No se pudo contactar con el servidor. Comprueba la dirección y la red.',
    'sftpConnect':
        'No se pudo conectar por SFTP. Comprueba el servidor, usuario y contraseña.',
    'smbAuth': 'Falló el acceso SMB. Comprueba usuario, dominio y contraseña.',
    'smbNotFound': 'No se encontró el recurso SMB o el archivo.',
    'smbRequest':
        'Falló la solicitud SMB ({type}). Comprueba permisos, red y cifrado.',
    'smbPaused': 'Transferencia SMB pausada.'
  },
  'pt': {
    'accessDenied': 'Acesso negado. Verifique as credenciais de ligação.',
    'redirects':
        'Use o endereço final do servidor; os redirecionamentos não são seguidos.',
    'httpStatus': 'Falha no pedido ao servidor (HTTP {status}).',
    'unreachable':
        'Não foi possível contactar o servidor. Verifique o endereço e a rede.',
    'sftpConnect':
        'Não foi possível ligar por SFTP. Verifique servidor, utilizador e palavra-passe.',
    'smbAuth':
        'Falha no acesso SMB. Verifique utilizador, domínio e palavra-passe.',
    'smbNotFound': 'Partilha SMB ou ficheiro não encontrado.',
    'smbRequest':
        'Falha no pedido SMB ({type}). Verifique permissões, rede e encriptação.',
    'smbPaused': 'Transferência SMB em pausa.'
  },
  'zh': {
    'accessDenied': '访问被拒绝。请检查连接凭据。',
    'redirects': '请使用服务器的最终地址；不会跟随重定向。',
    'httpStatus': '服务器请求失败（HTTP {status}）。',
    'unreachable': '无法连接服务器。请检查地址和网络。',
    'sftpConnect': '无法连接 SFTP。请检查服务器、用户名和密码。',
    'smbAuth': 'SMB 登录失败。请检查用户名、域和密码。',
    'smbNotFound': '未找到 SMB 共享或文件。',
    'smbRequest': 'SMB 请求失败（{type}）。请检查共享权限、网络和加密设置。',
    'smbPaused': 'SMB 传输已暂停。'
  },
  'ja': {
    'accessDenied': 'アクセスが拒否されました。接続認証情報を確認してください。',
    'redirects': '最終的なサーバー URL を使用してください。リダイレクトには対応していません。',
    'httpStatus': 'サーバーへの要求に失敗しました（HTTP {status}）。',
    'unreachable': 'サーバーに接続できません。アドレスとネットワークを確認してください。',
    'sftpConnect': 'SFTP に接続できません。サーバー、ユーザー名、パスワードを確認してください。',
    'smbAuth': 'SMB サインインに失敗しました。ユーザー名、ドメイン、パスワードを確認してください。',
    'smbNotFound': 'SMB 共有またはファイルが見つかりません。',
    'smbRequest': 'SMB 要求に失敗しました（{type}）。共有権限、ネットワーク、暗号化設定を確認してください。',
    'smbPaused': 'SMB 転送を一時停止しました。'
  },
  'ko': {
    'accessDenied': '접근이 거부되었습니다. 연결 자격 증명을 확인하세요.',
    'redirects': '최종 서버 주소를 사용하세요. 리디렉션은 따르지 않습니다.',
    'httpStatus': '서버 요청 실패 (HTTP {status}).',
    'unreachable': '서버에 연결할 수 없습니다. 주소와 네트워크를 확인하세요.',
    'sftpConnect': 'SFTP에 연결할 수 없습니다. 서버, 사용자 이름, 비밀번호를 확인하세요.',
    'smbAuth': 'SMB 로그인에 실패했습니다. 사용자 이름, 도메인, 비밀번호를 확인하세요.',
    'smbNotFound': 'SMB 공유 또는 파일을 찾을 수 없습니다.',
    'smbRequest': 'SMB 요청 실패 ({type}). 공유 권한, 네트워크 및 암호화 설정을 확인하세요.',
    'smbPaused': 'SMB 전송이 일시 중지되었습니다.'
  },
  'ar': {
    'accessDenied': 'تم رفض الوصول. تحقق من بيانات اعتماد الاتصال.',
    'redirects':
        'استخدم عنوان الخادم النهائي؛ لا تتم متابعة عمليات إعادة التوجيه.',
    'httpStatus': 'فشل طلب الخادم (HTTP {status}).',
    'unreachable': 'تعذر الوصول إلى الخادم. تحقق من عنوانه والشبكة.',
    'sftpConnect':
        'تعذر الاتصال عبر SFTP. تحقق من الخادم واسم المستخدم وكلمة المرور.',
    'smbAuth':
        'فشل تسجيل الدخول إلى SMB. تحقق من اسم المستخدم والنطاق وكلمة المرور.',
    'smbNotFound': 'لم يتم العثور على مشاركة SMB أو الملف.',
    'smbRequest':
        'فشل طلب SMB ({type}). تحقق من أذونات المشاركة والشبكة وإعداد التشفير.',
    'smbPaused': 'تم إيقاف نقل SMB مؤقتًا.'
  },
};
