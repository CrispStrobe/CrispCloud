import 'package:flutter/widgets.dart';

import '../services/fuse_mount_service.dart';

class MountBackendStrings {
  MountBackendStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  List<String> get _labels => _strings[language] ?? _strings['en']!;
  String get title => _labels[0];
  String label(MacFuseBackend backend) => _labels[backend.index + 1];
  String get kernelWarning =>
      _kernelWarnings[language] ?? _kernelWarnings['en']!;
  List<String> get _fuseT => _fuseTTerms[language] ?? _fuseTTerms['en']!;
  String get fuseTTitle => _fuseT[0];
  String get fuseTMessage => _fuseT[1];
  String get fuseTAccept => _fuseT[2];
  String get rcloneHint => _rcloneHints[language] ?? _rcloneHints['en']!;
  String get rcloneMissing =>
      (_rcloneErrors[language] ?? _rcloneErrors['en']!)[0];
  String get rcloneFailed =>
      (_rcloneErrors[language] ?? _rcloneErrors['en']!)[1];

  static const _rcloneErrors = <String, List<String>>{
    'en': [
      'rclone was not found. Install it separately.',
      'The rclone NFS mount failed.',
    ],
    'de': [
      'rclone wurde nicht gefunden. Installieren Sie es separat.',
      'Die rclone-NFS-Einbindung ist fehlgeschlagen.',
    ],
    'fr': [
      'rclone est introuvable. Installez-le séparément.',
      'Le montage NFS rclone a échoué.',
    ],
    'es': [
      'No se encontró rclone. Instálalo por separado.',
      'Falló el montaje NFS de rclone.',
    ],
    'pt': [
      'Não foi encontrado o rclone. Instale-o separadamente.',
      'A montagem NFS do rclone falhou.',
    ],
    'zh': ['找不到 rclone。请单独安装。', 'rclone NFS 挂载失败。'],
    'ja': ['rclone が見つかりません。別途インストールしてください。', 'rclone NFS のマウントに失敗しました。'],
    'ko': ['rclone을 찾을 수 없습니다. 별도로 설치하세요.', 'rclone NFS 마운트에 실패했습니다.'],
    'ar': [
      'تعذر العثور على rclone. ثبّته بشكل منفصل.',
      'فشل تثبيت rclone NFS.',
    ],
  };

  static const _rcloneHints = <String, String>{
    'en': 'Enter an independently configured rclone remote, for example work:documents. This read-only NFS mount is available to local processes.',
    'de': 'Geben Sie ein separat eingerichtetes rclone-Ziel ein, zum Beispiel arbeit:dokumente. Diese schreibgeschützte NFS-Einbindung ist für lokale Prozesse erreichbar.',
    'fr': 'Saisissez un distant rclone configuré séparément, par exemple travail:documents. Ce montage NFS en lecture seule est accessible aux processus locaux.',
    'es': 'Introduce un remoto de rclone configurado por separado, por ejemplo trabajo:documentos. Este montaje NFS de solo lectura es accesible a procesos locales.',
    'pt': 'Indique um remoto rclone configurado separadamente, por exemplo trabalho:documentos. Esta montagem NFS só de leitura é acessível aos processos locais.',
    'zh': '输入单独配置的 rclone 远程位置，例如 work:documents。此只读 NFS 挂载可供本地进程访问。',
    'ja': '別途設定した rclone リモート（例：work:documents）を入力してください。この読み取り専用 NFS マウントはローカルプロセスから利用できます。',
    'ko': '별도로 구성한 rclone 원격 경로(예: work:documents)를 입력하세요. 이 읽기 전용 NFS 마운트는 로컬 프로세스에서 접근할 수 있습니다.',
    'ar': 'أدخل وجهة rclone مُعدّة بشكل مستقل، مثل work:documents. يمكن للعمليات المحلية الوصول إلى تثبيت NFS للقراءة فقط.',
  };

  static const _fuseTTerms = <String, List<String>>{
    'en': [
      'FUSE-T use',
      'FUSE-T is installed separately. This option is for non-commercial use of FUSE-T. You are responsible for checking its license: https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      'I use FUSE-T non-commercially',
    ],
    'de': [
      'FUSE-T verwenden',
      'FUSE-T wird separat installiert. Diese Option ist für die nichtkommerzielle Nutzung von FUSE-T vorgesehen. Bitte prüfen Sie die Lizenz: https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      'Ich nutze FUSE-T nichtkommerziell',
    ],
    'fr': [
      'Utilisation de FUSE-T',
      'FUSE-T est installé séparément. Cette option est réservée à une utilisation non commerciale de FUSE-T. Vérifiez sa licence : https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      'J’utilise FUSE-T à titre non commercial',
    ],
    'es': [
      'Uso de FUSE-T',
      'FUSE-T se instala por separado. Esta opción es para uso no comercial de FUSE-T. Revisa su licencia: https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      'Uso FUSE-T de forma no comercial',
    ],
    'pt': [
      'Utilização do FUSE-T',
      'O FUSE-T é instalado separadamente. Esta opção destina-se à utilização não comercial do FUSE-T. Consulte a licença: https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      'Utilizo o FUSE-T sem fins comerciais',
    ],
    'zh': [
      '使用 FUSE-T',
      'FUSE-T 需单独安装。此选项仅供非商业用途使用 FUSE-T。请自行查看其许可证：https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      '我以非商业用途使用 FUSE-T',
    ],
    'ja': [
      'FUSE-T の使用',
      'FUSE-T は別途インストールします。このオプションは FUSE-T の非商用利用向けです。ライセンスをご確認ください：https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      'FUSE-T を非商用で使用します',
    ],
    'ko': [
      'FUSE-T 사용',
      'FUSE-T는 별도로 설치됩니다. 이 옵션은 FUSE-T의 비상업적 사용을 위한 것입니다. 라이선스를 확인하세요: https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      'FUSE-T를 비상업적으로 사용합니다',
    ],
    'ar': [
      'استخدام FUSE-T',
      'يُثبّت FUSE-T بشكل منفصل. هذا الخيار للاستخدام غير التجاري لـ FUSE-T. يرجى مراجعة الترخيص: https://github.com/macos-fuse-t/fuse-t/blob/main/License.txt',
      'أستخدم FUSE-T استخدامًا غير تجاري',
    ],
  };

  static const _kernelWarnings = <String, String>{
    'en': 'Requires kernel-extension approval and Reduced Security on Apple silicon.',
    'de': 'Erfordert die Genehmigung der Kernel-Erweiterung und reduzierte Sicherheit auf Apple Silicon.',
    'fr': 'Nécessite l’approbation de l’extension noyau et une sécurité réduite sur Apple Silicon.',
    'es': 'Requiere aprobar la extensión del núcleo y seguridad reducida en Apple Silicon.',
    'pt': 'Requer aprovação da extensão do kernel e segurança reduzida no Apple Silicon.',
    'zh': '需要批准内核扩展；Apple 芯片 Mac 还需降低安全性。',
    'ja': 'カーネル拡張の許可と、Appleシリコンではセキュリティの低減が必要です。',
    'ko': '커널 확장 승인과 Apple 실리콘의 보안 수준 완화가 필요합니다.',
    'ar': 'يتطلب الموافقة على امتداد النواة وتقليل الأمان على أجهزة Apple silicon.',
  };

  static const _strings = <String, List<String>>{
    'en': [
      'Mount backend',
      'Automatic (macFUSE FSKit)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (kernel extension)',
      'rclone NFS (experimental)',
    ],
    'de': [
      'Einbindungsart',
      'Automatisch (macFUSE FSKit)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (Kernel-Erweiterung)',
      'rclone NFS (experimentell)',
    ],
    'fr': [
      'Moteur de montage',
      'Automatique (macFUSE FSKit)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (extension noyau)',
      'rclone NFS (expérimental)',
    ],
    'es': [
      'Motor de montaje',
      'Automático (macFUSE FSKit)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (extensión del núcleo)',
      'rclone NFS (experimental)',
    ],
    'pt': [
      'Motor de montagem',
      'Automático (macFUSE FSKit)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (extensão do kernel)',
      'rclone NFS (experimental)',
    ],
    'zh': [
      '挂载后端',
      '自动（macFUSE FSKit）',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE（内核扩展）',
      'rclone NFS（实验性）',
    ],
    'ja': [
      'マウント方式',
      '自動（macFUSE FSKit）',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE（カーネル拡張）',
      'rclone NFS（試験的）',
    ],
    'ko': [
      '마운트 백엔드',
      '자동 (macFUSE FSKit)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (커널 확장)',
      'rclone NFS (실험적)',
    ],
    'ar': [
      'واجهة التثبيت',
      'تلقائي (macFUSE FSKit)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (امتداد النواة)',
      'rclone NFS (تجريبي)',
    ],
  };
}
