import 'package:flutter/widgets.dart';

import 'image_editor_strings.dart';

/// Media-specific strings plus the existing translated editor commands.
/// Rows are en, de, fr, es, pt, zh, ja, ko, ar; coverage is tested explicitly.
abstract final class MediaEditorStrings {
  static const languages = ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'];
  static const rows = <List<String>>[
    ['Audio editor', 'Audioeditor', 'Éditeur audio', 'Editor de audio', 'Editor de áudio', '音频编辑器', '音声エディター', '오디오 편집기', 'محرر الصوت'],
    ['Video editor', 'Videoeditor', 'Éditeur vidéo', 'Editor de vídeo', 'Editor de vídeo', '视频编辑器', '動画エディター', '동영상 편집기', 'محرر الفيديو'],
    ['Loading media…', 'Medien werden geladen…', 'Chargement du média…', 'Cargando contenido…', 'Carregando mídia…', '正在加载媒体…', 'メディアを読み込み中…', '미디어 불러오는 중…', 'جارٍ تحميل الوسائط…'],
    ['Export copy', 'Kopie exportieren', 'Exporter une copie', 'Exportar copia', 'Exportar cópia', '导出副本', 'コピーを書き出す', '사본 내보내기', 'تصدير نسخة'],
    ['Copy exported', 'Kopie exportiert', 'Copie exportée', 'Copia exportada', 'Cópia exportada', '副本已导出', 'コピーを書き出しました', '사본을 내보냈습니다', 'تم تصدير النسخة'],
    ['Exporting…', 'Wird exportiert…', 'Exportation…', 'Exportando…', 'Exportando…', '正在导出…', '書き出し中…', '내보내는 중…', 'جارٍ التصدير…'],
    ['Saving copy…', 'Kopie wird gespeichert…', 'Enregistrement de la copie…', 'Guardando copia…', 'Salvando cópia…', '正在保存副本…', 'コピーを保存中…', '사본 저장 중…', 'جارٍ حفظ النسخة…'],
    ['Cancel export', 'Export abbrechen', 'Annuler l’exportation', 'Cancelar exportación', 'Cancelar exportação', '取消导出', '書き出しをキャンセル', '내보내기 취소', 'إلغاء التصدير'],
    ['Preview edit', 'Bearbeitung vorhören', 'Aperçu des modifications', 'Vista previa de la edición', 'Prévia da edição', '预览编辑结果', '編集結果をプレビュー', '편집 미리 보기', 'معاينة التعديلات'],
    ['Source preview', 'Originalvorschau', 'Aperçu de la source', 'Vista previa del original', 'Prévia do original', '原始媒体预览', '元のメディアのプレビュー', '원본 미리 보기', 'معاينة المصدر'],
    ['Edited preview', 'Bearbeitete Vorschau', 'Aperçu modifié', 'Vista previa editada', 'Prévia editada', '编辑结果预览', '編集結果のプレビュー', '편집 결과 미리 보기', 'معاينة النتيجة'],
    ['Play', 'Wiedergabe', 'Lire', 'Reproducir', 'Reproduzir', '播放', '再生', '재생', 'تشغيل'],
    ['Pause', 'Pause', 'Pause', 'Pausar', 'Pausar', '暂停', '一時停止', '일시 정지', 'إيقاف مؤقت'],
    ['Trim', 'Zuschneiden', 'Rogner la durée', 'Recortar duración', 'Cortar duração', '裁剪时长', 'トリミング', '길이 자르기', 'قص المدة'],
    ['Start', 'Anfang', 'Début', 'Inicio', 'Início', '开始', '開始', '시작', 'البداية'],
    ['End', 'Ende', 'Fin', 'Fin', 'Fim', '结束', '終了', '끝', 'النهاية'],
    ['Gain', 'Verstärkung', 'Gain', 'Ganancia', 'Ganho', '增益', 'ゲイン', '게인', 'الكسب'],
    ['Fade in', 'Einblenden', 'Fondu entrant', 'Fundido de entrada', 'Fade de entrada', '淡入', 'フェードイン', '페이드 인', 'تلاشي البداية'],
    ['Fade out', 'Ausblenden', 'Fondu sortant', 'Fundido de salida', 'Fade de saída', '淡出', 'フェードアウト', '페이드 아웃', 'تلاشي النهاية'],
    ['Mute', 'Stummschalten', 'Couper le son', 'Silenciar', 'Silenciar', '静音', 'ミュート', '음소거', 'كتم الصوت'],
    ['Rotate clockwise', 'Im Uhrzeigersinn drehen', 'Tourner à droite', 'Girar a la derecha', 'Girar à direita', '顺时针旋转', '右に回転', '시계 방향 회전', 'تدوير مع عقارب الساعة'],
    ['Crop', 'Bildausschnitt', 'Recadrer', 'Recortar imagen', 'Recortar imagem', '裁剪画面', '切り抜き', '화면 자르기', 'اقتصاص الصورة'],
    ['Square', 'Quadrat', 'Carré', 'Cuadrado', 'Quadrado', '正方形', '正方形', '정사각형', 'مربع'],
    ['Landscape', 'Querformat', 'Paysage', 'Horizontal', 'Paisagem', '横向', '横向き', '가로', 'أفقي'],
    ['Portrait', 'Hochformat', 'Portrait', 'Vertical', 'Retrato', '纵向', '縦向き', '세로', 'عمودي'],
    ['Horizontal position', 'Horizontale Position', 'Position horizontale', 'Posición horizontal', 'Posição horizontal', '水平位置', '水平位置', '가로 위치', 'الموضع الأفقي'],
    ['Vertical position', 'Vertikale Position', 'Position verticale', 'Posición vertical', 'Posição vertical', '垂直位置', '垂直位置', '세로 위치', 'الموضع العمودي'],
    ['Output height', 'Ausgabehöhe', 'Hauteur de sortie', 'Altura de salida', 'Altura de saída', '输出高度', '出力の高さ', '출력 높이', 'ارتفاع الإخراج'],
    ['Full resolution', 'Volle Auflösung', 'Pleine résolution', 'Resolución completa', 'Resolução completa', '完整分辨率', '元の解像度', '전체 해상도', 'الدقة الكاملة'],
    ['File name', 'Dateiname', 'Nom du fichier', 'Nombre del archivo', 'Nome do arquivo', '文件名', 'ファイル名', '파일 이름', 'اسم الملف'],
    ['Create copy', 'Kopie erstellen', 'Créer une copie', 'Crear copia', 'Criar cópia', '创建副本', 'コピーを作成', '사본 만들기', 'إنشاء نسخة'],
    ['Export changes before closing?', 'Änderungen vor dem Schließen exportieren?', 'Exporter les modifications avant de fermer ?', '¿Exportar los cambios antes de cerrar?', 'Exportar as alterações antes de fechar?', '关闭前导出更改？', '閉じる前に変更を書き出しますか？', '닫기 전에 변경 사항을 내보낼까요?', 'هل تريد تصدير التعديلات قبل الإغلاق؟'],
    ['Could not open media', 'Medium konnte nicht geöffnet werden', 'Impossible d’ouvrir le média', 'No se pudo abrir el contenido', 'Não foi possível abrir a mídia', '无法打开媒体', 'メディアを開けませんでした', '미디어를 열 수 없습니다', 'تعذر فتح الوسائط'],
    ['Could not export media', 'Medium konnte nicht exportiert werden', 'Impossible d’exporter le média', 'No se pudo exportar el contenido', 'Não foi possível exportar a mídia', '无法导出媒体', 'メディアを書き出せませんでした', '미디어를 내보낼 수 없습니다', 'تعذر تصدير الوسائط'],
    ['Export cancelled', 'Export abgebrochen', 'Exportation annulée', 'Exportación cancelada', 'Exportação cancelada', '导出已取消', '書き出しをキャンセルしました', '내보내기가 취소되었습니다', 'تم إلغاء التصدير'],
    ['This media format cannot be edited on this platform.', 'Dieses Medienformat kann auf dieser Plattform nicht bearbeitet werden.', 'Ce format ne peut pas être modifié sur cette plateforme.', 'Este formato no se puede editar en esta plataforma.', 'Este formato não pode ser editado nesta plataforma.', '此平台无法编辑该媒体格式。', 'このプラットフォームではこの形式を編集できません。', '이 플랫폼에서는 이 미디어 형식을 편집할 수 없습니다.', 'لا يمكن تحرير هذا التنسيق على هذه المنصة.'],
    ['The storage account changed. Reopen the file before exporting.', 'Das Speicherkonto hat sich geändert. Öffnen Sie die Datei vor dem Export erneut.', 'Le compte de stockage a changé. Rouvrez le fichier avant de l’exporter.', 'La cuenta cambió. Vuelva a abrir el archivo antes de exportarlo.', 'A conta mudou. Reabra o arquivo antes de exportar.', '存储账户已更改。请重新打开文件再导出。', 'ストレージのアカウントが変わりました。ファイルを開き直してください。', '저장소 계정이 변경되었습니다. 내보내기 전에 파일을 다시 여세요.', 'تغير حساب التخزين. أعد فتح الملف قبل التصدير.'],
    ['Cloud media editing is limited to 64 MiB per file.', 'Cloud-Medien dürfen höchstens 64 MiB pro Datei groß sein.', 'L’édition dans le cloud est limitée à 64 Mio par fichier.', 'La edición en la nube está limitada a 64 MiB por archivo.', 'A edição na nuvem é limitada a 64 MiB por arquivo.', '云端媒体编辑限制为每个文件 64 MiB。', 'クラウドのメディア編集は1ファイル64 MiBまでです。', '클라우드 미디어 편집은 파일당 64 MiB로 제한됩니다.', 'يقتصر تحرير الوسائط السحابية على 64 MiB لكل ملف.'],
    ['Local media editing is limited to 2 GiB per file.', 'Lokale Medien dürfen höchstens 2 GiB pro Datei groß sein.', 'L’édition locale est limitée à 2 Gio par fichier.', 'La edición local está limitada a 2 GiB por archivo.', 'A edição local é limitada a 2 GiB por arquivo.', '本地媒体编辑限制为每个文件 2 GiB。', 'ローカルのメディア編集は1ファイル2 GiBまでです。', '로컬 미디어 편집은 파일당 2 GiB로 제한됩니다.', 'يقتصر تحرير الوسائط المحلية على 2 GiB لكل ملف.'],
    ['A file with this name already exists. Choose another name.', 'Eine Datei mit diesem Namen existiert bereits. Wählen Sie einen anderen Namen.', 'Un fichier porte déjà ce nom. Choisissez un autre nom.', 'Ya existe un archivo con ese nombre. Elija otro.', 'Já existe um arquivo com esse nome. Escolha outro.', '已存在同名文件。请选择其他名称。', '同名のファイルがあります。別の名前を指定してください。', '이 이름의 파일이 이미 있습니다. 다른 이름을 선택하세요.', 'يوجد ملف بهذا الاسم. اختر اسمًا آخر.'],
    ['Choose a simple filename with the correct extension.', 'Wählen Sie einen einfachen Dateinamen mit der richtigen Erweiterung.', 'Choisissez un nom simple avec la bonne extension.', 'Elija un nombre sencillo con la extensión correcta.', 'Escolha um nome simples com a extensão correta.', '请选择带正确扩展名的简单文件名。', '正しい拡張子を付けた簡単なファイル名を指定してください。', '올바른 확장자가 있는 간단한 파일 이름을 선택하세요.', 'اختر اسم ملف بسيطًا بالامتداد الصحيح.'],
    ['The destination could not be verified. Refresh the folder and try again.', 'Das Ziel konnte nicht geprüft werden. Aktualisieren Sie den Ordner und versuchen Sie es erneut.', 'La destination n’a pas pu être vérifiée. Actualisez le dossier et réessayez.', 'No se pudo verificar el destino. Actualice la carpeta e inténtelo de nuevo.', 'Não foi possível verificar o destino. Atualize a pasta e tente novamente.', '无法验证目标位置。请刷新文件夹后重试。', '保存先を確認できませんでした。フォルダーを更新して再試行してください。', '대상을 확인할 수 없습니다. 폴더를 새로 고친 후 다시 시도하세요.', 'تعذر التحقق من الوجهة. حدّث المجلد وحاول مجددًا.'],
    ['Access to this folder was not granted.', 'Der Zugriff auf diesen Ordner wurde nicht gewährt.', 'L’accès à ce dossier n’a pas été accordé.', 'No se concedió acceso a esta carpeta.', 'O acesso a esta pasta não foi concedido.', '未获得此文件夹的访问权限。', 'このフォルダーへのアクセスが許可されていません。', '이 폴더에 대한 접근이 허용되지 않았습니다.', 'لم يُمنح الوصول إلى هذا المجلد.'],
    ['The exported file could not be verified. Try exporting again.', 'Die exportierte Datei konnte nicht geprüft werden. Exportieren Sie erneut.', 'Le fichier exporté n’a pas pu être vérifié. Réessayez l’exportation.', 'No se pudo verificar el archivo exportado. Intente exportarlo de nuevo.', 'Não foi possível verificar o arquivo exportado. Tente exportar novamente.', '无法验证导出的文件。请重新导出。', '書き出したファイルを確認できませんでした。再度書き出してください。', '내보낸 파일을 확인할 수 없습니다. 다시 내보내세요.', 'تعذر التحقق من الملف المُصدّر. حاول التصدير مجددًا.'],
    ['Playback is unavailable. You can still edit and export.', 'Wiedergabe nicht verfügbar. Bearbeiten und Exportieren sind weiterhin möglich.', 'Lecture indisponible. Vous pouvez toujours modifier et exporter.', 'La reproducción no está disponible. Puede editar y exportar.', 'A reprodução não está disponível. Você pode editar e exportar.', '无法播放。您仍可编辑和导出。', '再生できません。編集と書き出しは利用できます。', '재생할 수 없습니다. 편집과 내보내기는 가능합니다.', 'التشغيل غير متاح. لا يزال بإمكانك التحرير والتصدير.'],
    ['Exports use WAV audio or MP4 video. The source file is kept.', 'Export als WAV-Audio oder MP4-Video. Die Quelldatei bleibt erhalten.', 'Export audio WAV ou vidéo MP4. Le fichier source est conservé.', 'Se exporta audio WAV o vídeo MP4. Se conserva el original.', 'Exporta áudio WAV ou vídeo MP4. O original é preservado.', '导出为 WAV 音频或 MP4 视频，并保留原始文件。', '音声はWAV、動画はMP4で書き出し、元のファイルを保持します。', 'WAV 오디오 또는 MP4 동영상으로 내보내며 원본은 유지됩니다.', 'يُصدّر الصوت بصيغة WAV والفيديو بصيغة MP4 مع الاحتفاظ بالمصدر.'],
  ];

  static final catalog = <String, Map<String, String>>{
    for (var i = 0; i < languages.length; i++)
      languages[i]: {for (final row in rows) row.first: row[i]},
  };

  static String forLanguage(String languageCode, String english) =>
      (catalog[languageCode] ?? catalog['en']!)[english] ??
      ImageEditorStrings.forLanguage(languageCode, english);
}

extension MediaEditorTranslations on BuildContext {
  String mediaTr(String english) => MediaEditorStrings.forLanguage(
    Localizations.localeOf(this).languageCode,
    english,
  );
}
