import 'package:flutter/widgets.dart';

import '../services/fuse_mount_service.dart';

class MountBackendStrings {
  MountBackendStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  List<String> get _labels => _strings[language] ?? _strings['en']!;
  String get title => _labels[0];
  String label(MacFuseBackend backend) => _labels[backend.index + 1];
  String get kernelWarning => _kernelWarnings[language] ?? _kernelWarnings['en']!;

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
      'Automatic (prefer FUSE-T)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (kernel extension)',
    ],
    'de': [
      'Einbindungsart',
      'Automatisch (FUSE-T bevorzugen)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (Kernel-Erweiterung)',
    ],
    'fr': [
      'Moteur de montage',
      'Automatique (FUSE-T prioritaire)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (extension noyau)',
    ],
    'es': [
      'Motor de montaje',
      'Automático (preferir FUSE-T)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (extensión del núcleo)',
    ],
    'pt': [
      'Motor de montagem',
      'Automático (preferir FUSE-T)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (extensão do kernel)',
    ],
    'zh': [
      '挂载后端',
      '自动（优先使用 FUSE-T）',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE（内核扩展）',
    ],
    'ja': [
      'マウント方式',
      '自動（FUSE-T を優先）',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE（カーネル拡張）',
    ],
    'ko': [
      '마운트 백엔드',
      '자동 (FUSE-T 우선)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (커널 확장)',
    ],
    'ar': [
      'واجهة التثبيت',
      'تلقائي (تفضيل FUSE-T)',
      'FUSE-T',
      'macFUSE (FSKit)',
      'macFUSE (امتداد النواة)',
    ],
  };
}
