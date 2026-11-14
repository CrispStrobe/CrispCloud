// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import 'package:flutter/widgets.dart';

String archiveZipRecoveryText(
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
  var value = index < 0 ? key : (_messages[key]?[index] ?? key);
  for (var i = 0; i < values.length; i++) {
    value = value.replaceAll('{$i}', '${values[i]}');
  }
  return value;
}

const _messages = <String, List<String>>{
  'Recover ZIP to new file…': [
    'ZIP in neue Datei retten…',
    'Récupérer le ZIP dans un nouveau fichier…',
    'Recuperar ZIP en un archivo nuevo…',
    'Recuperar ZIP para um novo arquivo…',
    '将 ZIP 恢复到新文件…',
    'ZIP を新しいファイルに復元…',
    'ZIP을 새 파일로 복구…',
    'استرداد ZIP إلى ملف جديد…',
  ],
  'ZIP recovery': [
    'ZIP-Wiederherstellung',
    'Récupération ZIP',
    'Recuperación ZIP',
    'Recuperação ZIP',
    'ZIP 恢复',
    'ZIP 復元',
    'ZIP 복구',
    'استرداد ZIP',
  ],
  'Scanning ZIP records…': [
    'ZIP-Einträge werden geprüft…',
    'Analyse des enregistrements ZIP…',
    'Analizando registros ZIP…',
    'Analisando registros ZIP…',
    '正在扫描 ZIP 记录…',
    'ZIP レコードを走査中…',
    'ZIP 레코드 검색 중…',
    'جارٍ فحص سجلات ZIP…',
  ],
  'Recovering files…': [
    'Dateien werden gerettet…',
    'Récupération des fichiers…',
    'Recuperando archivos…',
    'Recuperando arquivos…',
    '正在恢复文件…',
    'ファイルを復元中…',
    '파일 복구 중…',
    'جارٍ استرداد الملفات…',
  ],
  'Verifying recovered ZIP…': [
    'Gerettetes ZIP wird überprüft…',
    'Vérification du ZIP récupéré…',
    'Verificando ZIP recuperado…',
    'Verificando ZIP recuperado…',
    '正在验证恢复的 ZIP…',
    '復元した ZIP を検証中…',
    '복구한 ZIP 검증 중…',
    'جارٍ التحقق من ZIP المسترد…',
  ],
  'Saving new ZIP…': [
    'Neues ZIP wird gespeichert…',
    'Enregistrement du nouveau ZIP…',
    'Guardando el nuevo ZIP…',
    'Salvando o novo ZIP…',
    '正在保存新 ZIP…',
    '新しい ZIP を保存中…',
    '새 ZIP 저장 중…',
    'جارٍ حفظ ZIP الجديد…',
  ],
  'New ZIP filename': [
    'Name der neuen ZIP-Datei',
    'Nom du nouveau fichier ZIP',
    'Nombre del nuevo ZIP',
    'Nome do novo arquivo ZIP',
    '新 ZIP 文件名',
    '新しい ZIP ファイル名',
    '새 ZIP 파일 이름',
    'اسم ملف ZIP الجديد',
  ],
  'Recover selected': [
    'Auswahl retten',
    'Récupérer la sélection',
    'Recuperar selección',
    'Recuperar seleção',
    '恢复所选项',
    '選択項目を復元',
    '선택 항목 복구',
    'استرداد المحدد',
  ],
  'Ready for recovery': [
    'Zur Wiederherstellung bereit',
    'Prêt à récupérer',
    'Listo para recuperar',
    'Pronto para recuperar',
    '可恢复',
    '復元可能',
    '복구 가능',
    'جاهز للاسترداد',
  ],
  'Excluded': [
    'Ausgeschlossen',
    'Exclu',
    'Excluido',
    'Excluído',
    '已排除',
    '除外',
    '제외됨',
    'مستبعد',
  ],
  '{0} ready · {1} excluded · {2} selected': [
    '{0} bereit · {1} ausgeschlossen · {2} ausgewählt',
    '{0} prêts · {1} exclus · {2} sélectionnés',
    '{0} listos · {1} excluidos · {2} seleccionados',
    '{0} prontos · {1} excluídos · {2} selecionados',
    '{0} 项可恢复 · {1} 项已排除 · {2} 项已选',
    '復元可能 {0} · 除外 {1} · 選択 {2}',
    '복구 가능 {0} · 제외 {1} · 선택 {2}',
    '{0} جاهز · {1} مستبعد · {2} محدد',
  ],
  'Select all': [
    'Alle auswählen',
    'Tout sélectionner',
    'Seleccionar todo',
    'Selecionar tudo',
    '全选',
    'すべて選択',
    '모두 선택',
    'تحديد الكل',
  ],
  'Clear selection': [
    'Auswahl aufheben',
    'Effacer la sélection',
    'Borrar selección',
    'Limpar seleção',
    '清除选择',
    '選択を解除',
    '선택 해제',
    'مسح التحديد',
  ],
  'Copy report': [
    'Bericht kopieren',
    'Copier le rapport',
    'Copiar informe',
    'Copiar relatório',
    '复制报告',
    'レポートをコピー',
    '보고서 복사',
    'نسخ التقرير',
  ],
  'Saved {0}': [
    '{0} gespeichert',
    '{0} enregistré',
    '{0} guardado',
    '{0} salvo',
    '已保存 {0}',
    '{0} を保存しました',
    '{0} 저장됨',
    'تم حفظ {0}',
  ],
  'Source SHA-256': [
    'SHA-256 der Quelle',
    'SHA-256 de la source',
    'SHA-256 del origen',
    'SHA-256 da origem',
    '源文件 SHA-256',
    '元ファイルの SHA-256',
    '원본 SHA-256',
    'SHA-256 للمصدر',
  ],
  'Review verified entries, then save them to a new ZIP. The original file is retained.':
      [
        'Geprüfte Einträge auswählen und als neues ZIP speichern. Die Originaldatei bleibt erhalten.',
        'Vérifiez les entrées, puis enregistrez-les dans un nouveau ZIP. Le fichier original est conservé.',
        'Revise las entradas verificadas y guárdelas en un ZIP nuevo. Se conserva el original.',
        'Revise as entradas verificadas e salve em um novo ZIP. O arquivo original é mantido.',
        '检查已验证的条目，然后保存到新 ZIP。原文件将保留。',
        '検証済み項目を確認し、新しい ZIP に保存します。元ファイルは保持されます。',
        '검증된 항목을 확인한 다음 새 ZIP으로 저장합니다. 원본 파일은 유지됩니다.',
        'راجع العناصر المتحقق منها ثم احفظها في ZIP جديد. يُحتفظ بالملف الأصلي.',
      ],
  'Limits: 64 MiB input, expanded contents and output. Unproven boundaries stop the scan.':
      [
        'Grenzen: je 64 MiB für Eingabe, entpackte Inhalte und Ausgabe. Unklare Datengrenzen beenden die Suche.',
        'Limites : 64 Mio pour l’entrée, les contenus décompressés et la sortie. Une limite incertaine arrête l’analyse.',
        'Límites: 64 MiB de entrada, contenido expandido y salida. Los límites inciertos detienen el análisis.',
        'Limites: 64 MiB de entrada, conteúdo expandido e saída. Limites incertos interrompem a análise.',
        '限制：输入、解压内容和输出各 64 MiB。遇到无法确认的边界将停止扫描。',
        '入力・展開内容・出力は各 64 MiB まで。境界を確認できない場合、走査を停止します。',
        '입력, 압축 해제 내용, 출력은 각각 64 MiB까지입니다. 경계를 확인할 수 없으면 검색을 멈춥니다.',
        'الحدود: 64 ميبيبايت لكل من الإدخال والمحتوى الموسع والإخراج. يتوقف الفحص عند حدود غير مؤكدة.',
      ],
  'The recovery job continues in the Operations queue.': [
    'Die Wiederherstellung läuft in der Auftragswarteschlange weiter.',
    'La récupération continue dans la file d’opérations.',
    'La recuperación continúa en la cola de operaciones.',
    'A recuperação continua na fila de operações.',
    '恢复任务将在操作队列中继续。',
    '復元ジョブは操作キューで続行します。',
    '복구 작업은 작업 대기열에서 계속됩니다.',
    'تستمر مهمة الاسترداد في قائمة انتظار العمليات.',
  ],
  'Scan the original ZIP again after restart. Saved digests and output receipts remain available in this job.':
      [
        'Nach einem Neustart das ursprüngliche ZIP erneut prüfen. Gespeicherte Prüfsummen und Ausgabebelege bleiben in diesem Auftrag verfügbar.',
        'Après redémarrage, analysez à nouveau le ZIP original. Les empreintes et reçus restent disponibles dans cette tâche.',
        'Tras reiniciar, analice el ZIP original de nuevo. Los hashes y comprobantes siguen disponibles en esta tarea.',
        'Após reiniciar, analise o ZIP original novamente. Os hashes e comprovantes continuam disponíveis nesta tarefa.',
        '重启后请重新扫描原 ZIP。此任务仍保留摘要和输出记录。',
        '再起動後は元の ZIP を再走査してください。このジョブにはハッシュと出力記録が残ります。',
        '재시작 후 원본 ZIP을 다시 검색하세요. 저장된 해시와 출력 기록은 이 작업에 남아 있습니다.',
        'افحص ZIP الأصلي مجددًا بعد إعادة التشغيل. تبقى البصمات وسجلات الإخراج متاحة في هذه المهمة.',
      ],
};
