import 'package:flutter/widgets.dart';

import '../models/panel_drag_data.dart';
import '../services/external_drop_source.dart';
import 'folder_drop_strings.dart';

class ExternalDropStrings {
  const ExternalDropStrings(this.context);
  final BuildContext context;

  String text(String key) {
    final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final index = const [
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    ].indexOf(language);
    return messages[key]![index < 0 ? 0 : index];
  }

  String failure(Object error) => error is ExternalDropException
      ? text(error.failure.name)
      : FolderDropStrings(context).failure(
          error is PanelDragException
              ? error
              : const PanelDragException(PanelDragFailure.unavailable),
        );

  static const messages = <String, List<String>>{
    'files': [
      'Dropped files',
      'Abgelegte Dateien',
      'Fichiers déposés',
      'Archivos soltados',
      'Ficheiros largados',
      '拖入的文件',
      'ドロップしたファイル',
      '드롭한 파일',
      'الملفات المُفلَتة',
    ],
    'foreground': [
      'Keep this review open until copying finishes. Dropped files are available only for this transfer.',
      'Lassen Sie diese Ansicht geöffnet, bis das Kopieren abgeschlossen ist. Abgelegte Dateien sind nur für diese Übertragung verfügbar.',
      'Gardez cette fenêtre ouverte jusqu’à la fin de la copie. Les fichiers déposés sont disponibles uniquement pour ce transfert.',
      'Mantén esta ventana abierta hasta que termine la copia. Los archivos soltados solo están disponibles para esta transferencia.',
      'Mantenha esta janela aberta até a cópia terminar. Os ficheiros largados só estão disponíveis para esta transferência.',
      '请保持此窗口打开，直到复制完成。拖入的文件仅在本次传输期间可用。',
      'コピーが完了するまでこの画面を開いたままにしてください。ドロップしたファイルは今回の転送でのみ使用できます。',
      '복사가 끝날 때까지 이 창을 열어 두세요. 드롭한 파일은 이 전송에서만 사용할 수 있습니다.',
      'أبقِ هذه النافذة مفتوحة حتى يكتمل النسخ. الملفات المُفلَتة متاحة لهذا النقل فقط.',
    ],
    'invalidItems': [
      'This drop contains an invalid name, unsupported link, or unreadable folder. Drop regular files or folders with accessible contents.',
      'Diese Auswahl enthält einen ungültigen Namen, einen nicht unterstützten Link oder einen unlesbaren Ordner. Legen Sie normale Dateien oder Ordner mit zugänglichem Inhalt ab.',
      'Ce dépôt contient un nom incorrect, un lien non pris en charge ou un dossier illisible. Déposez des fichiers ordinaires ou des dossiers au contenu accessible.',
      'La selección contiene un nombre no válido, un enlace no compatible o una carpeta ilegible. Suelta archivos normales o carpetas con contenido accesible.',
      'A seleção contém um nome inválido, uma ligação não suportada ou uma pasta ilegível. Largue ficheiros normais ou pastas com conteúdo acessível.',
      '拖入内容包含无效名称、不支持的链接或无法读取的文件夹。请拖入普通文件或内容可访问的文件夹。',
      '無効な名前、未対応のリンク、または読み取れないフォルダーが含まれています。通常のファイルか、内容にアクセスできるフォルダーをドロップしてください。',
      '잘못된 이름, 지원하지 않는 링크 또는 읽을 수 없는 폴더가 포함되어 있습니다. 일반 파일이나 내용을 읽을 수 있는 폴더를 드롭하세요.',
      'تحتوي العناصر على اسم غير صالح أو رابط غير مدعوم أو مجلد لا يمكن قراءته. أفلِت ملفات عادية أو مجلدات يمكن الوصول إلى محتوياتها.',
    ],
    'duplicateNames': [
      'The dropped items contain duplicate names in the same folder. Rename them or copy them separately.',
      'Die abgelegten Elemente enthalten doppelte Namen im selben Ordner. Benennen Sie sie um oder kopieren Sie sie getrennt.',
      'Les éléments déposés ont des noms identiques dans le même dossier. Renommez-les ou copiez-les séparément.',
      'Los elementos soltados tienen nombres duplicados en la misma carpeta. Cámbiales el nombre o cópialos por separado.',
      'Os itens largados têm nomes repetidos na mesma pasta. Altere os nomes ou copie-os separadamente.',
      '拖入的项目在同一文件夹中存在重名。请重命名或分别复制。',
      '同じフォルダー内に同名の項目があります。名前を変更するか、別々にコピーしてください。',
      '같은 폴더에 중복된 이름이 있습니다. 이름을 바꾸거나 따로 복사하세요.',
      'توجد أسماء مكررة في المجلد نفسه. غيّر أسماء العناصر أو انسخها بشكل منفصل.',
    ],
    'unavailable': [
      'The dropped files are no longer available or access was denied. Drop them again from their original location.',
      'Die abgelegten Dateien sind nicht mehr verfügbar oder der Zugriff wurde verweigert. Legen Sie sie erneut von ihrem ursprünglichen Speicherort ab.',
      'Les fichiers déposés ne sont plus disponibles ou leur accès a été refusé. Déposez-les à nouveau depuis leur emplacement d’origine.',
      'Los archivos ya no están disponibles o se denegó el acceso. Vuelve a soltarlos desde su ubicación original.',
      'Os ficheiros já não estão disponíveis ou o acesso foi negado. Largue-os novamente a partir da localização original.',
      '拖入的文件已不可用或访问被拒绝。请从原位置重新拖入。',
      'ドロップしたファイルが利用できないか、アクセスが拒否されました。元の場所からもう一度ドロップしてください。',
      '드롭한 파일을 사용할 수 없거나 접근이 거부되었습니다. 원래 위치에서 다시 드롭하세요.',
      'الملفات المُفلَتة لم تعد متاحة أو رُفض الوصول إليها. أفلِتها مجددًا من موقعها الأصلي.',
    ],
    'changed': [
      'A dropped file changed while it was being read. Refresh the original files and start a new copy review.',
      'Eine abgelegte Datei wurde während des Lesens geändert. Aktualisieren Sie die Originaldateien und starten Sie eine neue Kopierprüfung.',
      'Un fichier déposé a changé pendant sa lecture. Actualisez les originaux et ouvrez une nouvelle vérification de copie.',
      'Un archivo cambió mientras se leía. Actualiza los originales y abre una nueva revisión de copia.',
      'Um ficheiro foi alterado durante a leitura. Atualize os originais e inicie uma nova revisão da cópia.',
      '读取期间拖入的文件发生了变化。请刷新原始文件并重新开始复制审核。',
      '読み取り中にファイルが変更されました。元のファイルを更新して、コピーの確認をやり直してください。',
      '읽는 동안 파일이 변경되었습니다. 원본 파일을 새로 고친 후 복사를 다시 검토하세요.',
      'تغيّر ملف أثناء قراءته. حدّث الملفات الأصلية وابدأ مراجعة نسخ جديدة.',
    ],
    'tooLarge': [
      'This drop contains too many items or folder levels. Copy a smaller selection.',
      'Diese Auswahl enthält zu viele Elemente oder Ordnerebenen. Kopieren Sie eine kleinere Auswahl.',
      'Ce dépôt contient trop d’éléments ou de niveaux de dossiers. Copiez une sélection plus petite.',
      'La selección tiene demasiados elementos o niveles de carpetas. Copia una selección más pequeña.',
      'A seleção tem demasiados itens ou níveis de pastas. Copie uma seleção mais pequena.',
      '拖入内容包含过多项目或文件夹层级。请选择较小的范围进行复制。',
      '項目数またはフォルダー階層が多すぎます。選択範囲を小さくしてコピーしてください。',
      '항목이나 폴더 단계가 너무 많습니다. 더 적은 항목을 선택하여 복사하세요.',
      'تحتوي العناصر على عدد كبير من الملفات أو مستويات المجلدات. انسخ مجموعة أصغر.',
    ],
    'releaseFailed': [
      'Temporary access to a dropped file could not be released. The transfer source has been closed.',
      'Der temporäre Zugriff auf eine abgelegte Datei konnte nicht freigegeben werden. Die Übertragungsquelle wurde geschlossen.',
      'L’accès temporaire à un fichier déposé n’a pas pu être libéré. La source du transfert a été fermée.',
      'No se pudo liberar el acceso temporal a un archivo. El origen de la transferencia se ha cerrado.',
      'Não foi possível libertar o acesso temporário a um ficheiro. A origem da transferência foi fechada.',
      '无法释放拖入文件的临时访问权限。传输源已关闭。',
      '一時的なファイルアクセスを解放できませんでした。転送元は閉じられました。',
      '파일의 임시 접근 권한을 해제하지 못했습니다. 전송 원본은 닫혔습니다.',
      'تعذّر تحرير الوصول المؤقت إلى ملف مُفلَت. أُغلق مصدر النقل.',
    ],
  };
}
