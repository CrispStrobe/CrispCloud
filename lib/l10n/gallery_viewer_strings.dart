import 'package:flutter/widgets.dart';

/// The gallery viewer follows the same nine language choices as the app.
abstract final class GalleryViewerStrings {
  static const languages = ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'];

  // Values follow [languages]. English is the key and the unknown-locale
  // fallback, so system locales outside the app's catalog remain usable.
  static const translations = <String, List<String>>{
    'Image gallery': ['Bildergalerie', 'Galerie d’images', 'Galería de imágenes', 'Galeria de imagens', '图片库', '画像ギャラリー', '이미지 갤러리', 'معرض الصور'],
    'Close': ['Schließen', 'Fermer', 'Cerrar', 'Fechar', '关闭', '閉じる', '닫기', 'إغلاق'],
    'Previous image': ['Vorheriges Bild', 'Image précédente', 'Imagen anterior', 'Imagem anterior', '上一张图片', '前の画像', '이전 이미지', 'الصورة السابقة'],
    'Next image': ['Nächstes Bild', 'Image suivante', 'Imagen siguiente', 'Próxima imagem', '下一张图片', '次の画像', '다음 이미지', 'الصورة التالية'],
    'Fit image': ['Bild einpassen', 'Ajuster l’image', 'Ajustar imagen', 'Ajustar imagem', '适应窗口', '画像を画面に合わせる', '화면에 맞추기', 'ملاءمة الصورة'],
    'Actual size (1:1)': ['Originalgröße (1:1)', 'Taille réelle (1:1)', 'Tamaño real (1:1)', 'Tamanho real (1:1)', '实际大小 (1:1)', '実際のサイズ (1:1)', '실제 크기 (1:1)', 'الحجم الفعلي (1:1)'],
    'Zoom out': ['Verkleinern', 'Zoom arrière', 'Alejar', 'Reduzir', '缩小', '縮小', '축소', 'تصغير'],
    'Zoom in': ['Vergrößern', 'Zoom avant', 'Acercar', 'Ampliar', '放大', '拡大', '확대', 'تكبير'],
    'Rotate left': ['Nach links drehen', 'Pivoter à gauche', 'Girar a la izquierda', 'Girar à esquerda', '向左旋转', '左に回転', '왼쪽으로 회전', 'تدوير لليسار'],
    'Rotate right': ['Nach rechts drehen', 'Pivoter à droite', 'Girar a la derecha', 'Girar à direita', '向右旋转', '右に回転', '오른쪽으로 회전', 'تدوير لليمين'],
    'Flip horizontally': ['Horizontal spiegeln', 'Retourner horizontalement', 'Voltear horizontalmente', 'Inverter horizontalmente', '水平翻转', '左右反転', '좌우 반전', 'قلب أفقي'],
    'Flip vertically': ['Vertikal spiegeln', 'Retourner verticalement', 'Voltear verticalmente', 'Inverter verticalmente', '垂直翻转', '上下反転', '상하 반전', 'قلب عمودي'],
    'Start slideshow': ['Diashow starten', 'Lancer le diaporama', 'Iniciar presentación', 'Iniciar apresentação', '开始幻灯片', 'スライドショーを開始', '슬라이드 쇼 시작', 'بدء عرض الشرائح'],
    'Pause slideshow': ['Diashow pausieren', 'Suspendre le diaporama', 'Pausar presentación', 'Pausar apresentação', '暂停幻灯片', 'スライドショーを一時停止', '슬라이드 쇼 일시 정지', 'إيقاف عرض الشرائح مؤقتًا'],
    'Slideshow options': ['Diashow-Optionen', 'Options du diaporama', 'Opciones de presentación', 'Opções da apresentação', '幻灯片选项', 'スライドショーの設定', '슬라이드 쇼 옵션', 'خيارات عرض الشرائح'],
    'Interval': ['Intervall', 'Intervalle', 'Intervalo', 'Intervalo', '间隔', '間隔', '간격', 'الفاصل الزمني'],
    'Loop': ['Wiederholen', 'Répéter', 'Repetir', 'Repetir', '循环', '繰り返し', '반복', 'تكرار'],
    'Shuffle': ['Zufällige Reihenfolge', 'Ordre aléatoire', 'Orden aleatorio', 'Ordem aleatória', '随机播放', 'シャッフル', '순서 섞기', 'ترتيب عشوائي'],
    'Metadata': ['Metadaten', 'Métadonnées', 'Metadatos', 'Metadados', '元数据', 'メタデータ', '메타데이터', 'البيانات الوصفية'],
    'Filmstrip': ['Filmstreifen', 'Bande de vignettes', 'Tira de miniaturas', 'Faixa de miniaturas', '缩略图条', 'フィルムストリップ', '필름 스트립', 'شريط الصور'],
    'Compare images': ['Bilder vergleichen', 'Comparer les images', 'Comparar imágenes', 'Comparar imagens', '比较图片', '画像を比較', '이미지 비교', 'مقارنة الصور'],
    'Single image': ['Einzelbild', 'Image unique', 'Una imagen', 'Imagem única', '单张图片', '単一画像', '단일 이미지', 'صورة واحدة'],
    'Link zoom and pan': ['Zoom und Verschieben koppeln', 'Lier zoom et déplacement', 'Vincular zoom y desplazamiento', 'Vincular zoom e deslocamento', '同步缩放和平移', 'ズームと移動を連動', '확대 및 이동 연결', 'ربط التكبير والتحريك'],
    'Unlink zoom and pan': ['Zoom und Verschieben entkoppeln', 'Délier zoom et déplacement', 'Desvincular zoom y desplazamiento', 'Desvincular zoom e deslocamento', '取消同步缩放和平移', 'ズームと移動の連動を解除', '확대 및 이동 연결 해제', 'إلغاء ربط التكبير والتحريك'],
    'Edit image': ['Bild bearbeiten', 'Modifier l’image', 'Editar imagen', 'Editar imagem', '编辑图片', '画像を編集', '이미지 편집', 'تحرير الصورة'],
    'Save original copy': ['Original als Kopie speichern', 'Enregistrer une copie de l’original', 'Guardar copia del original', 'Salvar cópia do original', '保存原图副本', '元画像のコピーを保存', '원본 사본 저장', 'حفظ نسخة من الأصل'],
    'More': ['Mehr', 'Plus', 'Más', 'Mais', '更多', 'その他', '더 보기', 'المزيد'],
    'Dark background': ['Dunkler Hintergrund', 'Fond sombre', 'Fondo oscuro', 'Fundo escuro', '深色背景', '暗い背景', '어두운 배경', 'خلفية داكنة'],
    'Light background': ['Heller Hintergrund', 'Fond clair', 'Fondo claro', 'Fundo claro', '浅色背景', '明るい背景', '밝은 배경', 'خلفية فاتحة'],
    'Checkerboard background': ['Schachbretthintergrund', 'Fond en damier', 'Fondo de tablero', 'Fundo quadriculado', '棋盘格背景', '市松模様の背景', '체크 무늬 배경', 'خلفية مربعات'],
    'Smooth pixels': ['Pixel glätten', 'Lisser les pixels', 'Suavizar píxeles', 'Suavizar pixels', '平滑像素', 'ピクセルを滑らかに表示', '픽셀 부드럽게', 'تنعيم البكسلات'],
    'Reset view': ['Ansicht zurücksetzen', 'Réinitialiser la vue', 'Restablecer vista', 'Redefinir visualização', '重置视图', '表示をリセット', '보기 초기화', 'إعادة تعيين العرض'],
    'Loading image…': ['Bild wird geladen…', 'Chargement de l’image…', 'Cargando imagen…', 'Carregando imagem…', '正在加载图片…', '画像を読み込み中…', '이미지 불러오는 중…', 'جارٍ تحميل الصورة…'],
    'Could not load this image.': ['Dieses Bild konnte nicht geladen werden.', 'Impossible de charger cette image.', 'No se pudo cargar esta imagen.', 'Não foi possível carregar esta imagem.', '无法加载此图片。', 'この画像を読み込めませんでした。', '이 이미지를 불러올 수 없습니다.', 'تعذّر تحميل هذه الصورة.'],
    'Retry': ['Erneut versuchen', 'Réessayer', 'Reintentar', 'Tentar novamente', '重试', '再試行', '다시 시도', 'إعادة المحاولة'],
    'No images to display.': ['Keine Bilder vorhanden.', 'Aucune image à afficher.', 'No hay imágenes para mostrar.', 'Não há imagens para exibir.', '没有可显示的图片。', '表示する画像がありません。', '표시할 이미지가 없습니다.', 'لا توجد صور لعرضها.'],
    'Select two to four images to compare.': ['Wählen Sie zwei bis vier Bilder zum Vergleich.', 'Sélectionnez deux à quatre images à comparer.', 'Selecciona de dos a cuatro imágenes para comparar.', 'Selecione de duas a quatro imagens para comparar.', '请选择两到四张图片进行比较。', '比較する画像を2〜4枚選択してください。', '비교할 이미지를 2~4개 선택하세요.', 'حدّد صورتين إلى أربع صور للمقارنة.'],
    'Name': ['Name', 'Nom', 'Nombre', 'Nome', '名称', '名前', '이름', 'الاسم'],
    'Path': ['Pfad', 'Chemin', 'Ruta', 'Caminho', '路径', 'パス', '경로', 'المسار'],
    'Format': ['Format', 'Format', 'Formato', 'Formato', '格式', '形式', '형식', 'التنسيق'],
    'Dimensions': ['Abmessungen', 'Dimensions', 'Dimensiones', 'Dimensões', '尺寸', '寸法', '크기', 'الأبعاد'],
    'File size': ['Dateigröße', 'Taille du fichier', 'Tamaño del archivo', 'Tamanho do arquivo', '文件大小', 'ファイルサイズ', '파일 크기', 'حجم الملف'],
    'Modified': ['Geändert', 'Modifié', 'Modificado', 'Modificado', '修改时间', '更新日時', '수정 시간', 'آخر تعديل'],
    'Frames': ['Einzelbilder', 'Images', 'Fotogramas', 'Quadros', '帧数', 'フレーム数', '프레임', 'الإطارات'],
    'Preview only': ['Nur Vorschau', 'Aperçu uniquement', 'Solo vista previa', 'Somente prévia', '仅预览', 'プレビューのみ', '미리보기 전용', 'معاينة فقط'],
    'Preview transforms only. Use Edit image to save changes.': ['Drehung und Spiegelung gelten nur für die Vorschau. Änderungen über „Bild bearbeiten“ speichern.', 'Transformations d’aperçu uniquement. Utilisez Modifier l’image pour enregistrer.', 'Las transformaciones son solo de vista previa. Usa Editar imagen para guardarlas.', 'Transformações apenas na prévia. Use Editar imagem para salvar alterações.', '变换仅影响预览。请使用“编辑图片”保存更改。', '変形はプレビューのみです。保存するには「画像を編集」を使ってください。', '변환은 미리보기에만 적용됩니다. 저장하려면 이미지 편집을 사용하세요.', 'التحويلات للمعاينة فقط. استخدم تحرير الصورة لحفظ التغييرات.'],
    'Converted preview of the first frame.': ['Konvertierte Vorschau des ersten Einzelbilds.', 'Aperçu converti de la première image.', 'Vista previa convertida del primer fotograma.', 'Prévia convertida do primeiro quadro.', '已转换的首帧预览。', '最初のフレームを変換したプレビュー。', '첫 프레임의 변환된 미리보기입니다.', 'معاينة محوّلة للإطار الأول.'],
    'A copy was saved.': ['Eine Kopie wurde gespeichert.', 'Une copie a été enregistrée.', 'Se guardó una copia.', 'Uma cópia foi salva.', '已保存副本。', 'コピーを保存しました。', '사본을 저장했습니다.', 'تم حفظ نسخة.'],
    'Download started.': ['Download gestartet.', 'Téléchargement lancé.', 'Descarga iniciada.', 'Download iniciado.', '下载已开始。', 'ダウンロードを開始しました。', '다운로드가 시작되었습니다.', 'بدأ التنزيل.'],
    'The export could not be completed.': ['Der Export konnte nicht abgeschlossen werden.', 'L’exportation n’a pas pu être terminée.', 'No se pudo completar la exportación.', 'Não foi possível concluir a exportação.', '无法完成导出。', '書き出しを完了できませんでした。', '내보내기를 완료할 수 없습니다.', 'تعذّر إكمال التصدير.'],
    'This image’s source has changed. Refresh the folder before editing.': ['Die Bildquelle hat sich geändert. Aktualisieren Sie den Ordner vor dem Bearbeiten.', 'La source de l’image a changé. Actualisez le dossier avant de modifier.', 'El origen de la imagen cambió. Actualiza la carpeta antes de editar.', 'A origem da imagem mudou. Atualize a pasta antes de editar.', '图片来源已更改。请刷新文件夹后再编辑。', '画像のソースが変更されました。編集する前にフォルダーを更新してください。', '이미지 원본 위치가 변경되었습니다. 편집 전에 폴더를 새로 고치세요.', 'تغيّر مصدر الصورة. حدّث المجلد قبل التحرير.'],
    'This image’s source has changed. Close the viewer and reopen the folder.': ['Die Bildquelle hat sich geändert. Schließen Sie die Ansicht und öffnen Sie den Ordner erneut.', 'La source de l’image a changé. Fermez la visionneuse et rouvrez le dossier.', 'El origen de la imagen cambió. Cierra el visor y vuelve a abrir la carpeta.', 'A origem da imagem mudou. Feche o visualizador e abra a pasta novamente.', '图片来源已更改。请关闭查看器并重新打开文件夹。', '画像のソースが変更されました。ビューアーを閉じてフォルダーを開き直してください。', '이미지 원본 위치가 변경되었습니다. 뷰어를 닫고 폴더를 다시 여세요.', 'تغيّر مصدر الصورة. أغلق العارض وأعد فتح المجلد.'],
    'Loading original…': ['Original wird geladen…', 'Chargement de l’original…', 'Cargando original…', 'Carregando original…', '正在加载原图…', '元画像を読み込み中…', '원본 불러오는 중…', 'جارٍ تحميل الأصل…'],
    'View controls': ['Ansichtssteuerung', 'Commandes d’affichage', 'Controles de vista', 'Controles de visualização', '视图控制', '表示コントロール', '보기 컨트롤', 'عناصر التحكم بالعرض'],
    'Unknown': ['Unbekannt', 'Inconnu', 'Desconocido', 'Desconhecido', '未知', '不明', '알 수 없음', 'غير معروف'],
    'seconds': ['Sekunden', 'secondes', 'segundos', 'segundos', '秒', '秒', '초', 'ثوانٍ'],
    'Keyboard shortcuts': ['Tastenkürzel', 'Raccourcis clavier', 'Atajos de teclado', 'Atalhos do teclado', '键盘快捷键', 'キーボードショートカット', '키보드 단축키', 'اختصارات لوحة المفاتيح'],
    'First / last image': ['Erstes / letztes Bild', 'Première / dernière image', 'Primera / última imagen', 'Primeira / última imagem', '第一张 / 最后一张图片', '最初 / 最後の画像', '첫 이미지 / 마지막 이미지', 'الصورة الأولى / الأخيرة'],
    'Apply': ['Anwenden', 'Appliquer', 'Aplicar', 'Aplicar', '应用', '適用', '적용', 'تطبيق'],
    'Cancel': ['Abbrechen', 'Annuler', 'Cancelar', 'Cancelar', '取消', 'キャンセル', '취소', 'إلغاء'],
  };

  static String forLanguage(String languageCode, String english) {
    final index = languages.indexOf(languageCode);
    return index < 0 ? english : translations[english]?[index] ?? english;
  }

  static String translate(BuildContext context, String english) =>
      forLanguage(Localizations.localeOf(context).languageCode, english);
}

extension GalleryViewerTranslation on BuildContext {
  String galleryViewerTr(String english) =>
      GalleryViewerStrings.translate(this, english);
}
