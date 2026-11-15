// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'package:flutter/widgets.dart';

import 'archive_zip_recovery_strings.dart';

String archivePngCarvingText(
  BuildContext context,
  String key, [
  List<Object> values = const [],
]) {
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final index = const [
    'de',
    'fr',
    'es',
    'pt',
    'zh',
    'ja',
    'ko',
    'ar',
  ].indexOf(language);
  var value = index < 0
      ? key
      : (_messages[key]?[index] ?? archiveZipRecoveryText(context, key));
  for (var i = 0; i < values.length; i++) {
    value = value.replaceAll('{$i}', '${values[i]}');
  }
  return value;
}

const _messages = <String, List<String>>{
  'Recover PNG images to ZIP…': [
    'PNG-Bilder in ZIP retten…',
    'Récupérer des images PNG dans un ZIP…',
    'Recuperar imágenes PNG en ZIP…',
    'Recuperar imagens PNG para ZIP…',
    '恢复 PNG 图像到 ZIP…',
    'PNG 画像を ZIP に復元…',
    'PNG 이미지를 ZIP으로 복구…',
    'استرداد صور PNG إلى ZIP…',
  ],
  'PNG carving': [
    'PNG-Bildrettung',
    'Récupération d’images PNG',
    'Recuperación de imágenes PNG',
    'Recuperação de imagens PNG',
    'PNG 图像恢复',
    'PNG 画像の復元',
    'PNG 이미지 복구',
    'استرداد صور PNG',
  ],
  'Scanning for PNG images…': [
    'PNG-Bilder werden gesucht…',
    'Recherche d’images PNG…',
    'Buscando imágenes PNG…',
    'Procurando imagens PNG…',
    '正在扫描 PNG 图像…',
    'PNG 画像を走査中…',
    'PNG 이미지 검색 중…',
    'جارٍ البحث عن صور PNG…',
  ],
  'Review validated PNG images, then save them with an offset and hash report in a new ZIP. The original file is retained.':
      [
        'Prüfen Sie die validierten PNG-Bilder und speichern Sie sie mit einem Bericht über Offsets und Prüfsummen in einem neuen ZIP. Die Originaldatei bleibt erhalten.',
        'Examinez les images PNG validées, puis enregistrez-les avec un rapport des positions et empreintes dans un nouveau ZIP. Le fichier original est conservé.',
        'Revise las imágenes PNG validadas y guárdelas con un informe de posiciones y hashes en un ZIP nuevo. Se conserva el archivo original.',
        'Revise as imagens PNG validadas e salve-as com um relatório de posições e hashes em um novo ZIP. O arquivo original é preservado.',
        '查看已验证的 PNG 图像，然后将其与偏移量和哈希报告一起保存到新的 ZIP。原始文件保持不变。',
        '検証済みの PNG 画像を確認し、位置とハッシュのレポートとともに新しい ZIP に保存します。元のファイルは保持されます。',
        '검증된 PNG 이미지를 검토하고 위치 및 해시 보고서와 함께 새 ZIP으로 저장하세요. 원본 파일은 보존됩니다.',
        'راجع صور PNG التي تم التحقق منها، ثم احفظها مع تقرير المواضع والبصمات في ملف ZIP جديد. يُحتفظ بالملف الأصلي.',
      ],
  'Limits: 64 MiB input and output. Only supported complete PNG images are offered; names, directories and fragmented files are not reconstructed.':
      [
        'Grenzen: jeweils 64 MiB für Eingabe und Ausgabe. Nur unterstützte, vollständige PNG-Bilder werden angeboten; Namen, Verzeichnisse und fragmentierte Dateien werden nicht rekonstruiert.',
        'Limites : 64 Mio en entrée et en sortie. Seules les images PNG complètes et prises en charge sont proposées ; les noms, dossiers et fichiers fragmentés ne sont pas reconstitués.',
        'Límites: 64 MiB de entrada y salida. Solo se ofrecen imágenes PNG completas y compatibles; no se reconstruyen nombres, carpetas ni archivos fragmentados.',
        'Limites: 64 MiB de entrada e saída. Apenas imagens PNG completas e compatíveis são oferecidas; nomes, pastas e arquivos fragmentados não são reconstruídos.',
        '限制：输入和输出各 64 MiB。仅提供支持的完整 PNG 图像；不会重建名称、目录或碎片化文件。',
        '上限：入力と出力は各 64 MiB。対応する完全な PNG 画像のみを復元します。名前、ディレクトリ、断片化したファイルは再構築しません。',
        '제한: 입력과 출력 각각 64 MiB. 지원되는 완전한 PNG 이미지만 제공하며 이름, 디렉터리 및 조각난 파일은 재구성하지 않습니다.',
        'الحدود: 64 MiB لكل من الإدخال والإخراج. تُعرض صور PNG الكاملة والمدعومة فقط؛ لا تُعاد أسماء الملفات أو المجلدات أو الملفات المجزأة.',
      ],
  'Profile: non-interlaced 8-bit PNG. Indexed color and animation are unsupported.':
      [
        'Profil: 8-Bit-PNG ohne Interlacing. Indizierte Farben und Animationen werden nicht unterstützt.',
        'Profil : PNG 8 bits non entrelacé. Les couleurs indexées et les animations ne sont pas prises en charge.',
        'Perfil: PNG de 8 bits sin entrelazado. No admite color indexado ni animación.',
        'Perfil: PNG de 8 bits sem entrelaçamento. Cor indexada e animação não são compatíveis.',
        '支持范围：非交错 8 位 PNG。不支持索引色和动画。',
        '対応範囲：非インターレースの 8 ビット PNG。インデックスカラーとアニメーションは非対応です。',
        '지원 범위: 비인터레이스 8비트 PNG. 인덱스 색상과 애니메이션은 지원하지 않습니다.',
        'النطاق: PNG بعمق 8 بت دون تشابك. الألوان المفهرسة والرسوم المتحركة غير مدعومة.',
      ],
  'Scan the original file again after restart and review the PNG candidates. Saved digests and output receipts remain available in this job.':
      [
        'Scannen Sie die Originaldatei nach dem Neustart erneut und prüfen Sie die PNG-Kandidaten. Gespeicherte Prüfsummen und Ausgabebelege bleiben in diesem Auftrag verfügbar.',
        'Après le redémarrage, analysez à nouveau le fichier original et examinez les candidats PNG. Les empreintes et reçus de sortie restent disponibles dans cette tâche.',
        'Tras reiniciar, vuelva a analizar el archivo original y revise los candidatos PNG. Los hashes y comprobantes de salida guardados siguen disponibles en esta tarea.',
        'Após reiniciar, examine novamente o arquivo original e revise os candidatos PNG. Os hashes e comprovantes de saída salvos continuam disponíveis nesta tarefa.',
        '重启后，请重新扫描原始文件并查看 PNG 候选项。已保存的摘要和输出凭据仍可在此任务中查看。',
        '再起動後は元のファイルを再走査し、PNG 候補を確認してください。保存済みのハッシュと出力記録はこのジョブに残ります。',
        '다시 시작한 후 원본 파일을 다시 검색하고 PNG 후보를 검토하세요. 저장된 해시와 출력 기록은 이 작업에 남아 있습니다.',
        'بعد إعادة التشغيل، افحص الملف الأصلي مجددًا وراجع مرشحات PNG. تبقى البصمات وإيصالات الإخراج المحفوظة متاحة في هذه المهمة.',
      ],
};
