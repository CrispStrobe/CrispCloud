import 'package:flutter/widgets.dart';

import '../models/panel_drag_data.dart';

class FolderDropStrings {
  const FolderDropStrings(this.context);
  final BuildContext context;

  String failure(Object error) {
    final failure = error is PanelDragException
        ? error.failure
        : PanelDragFailure.unavailable;
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
    return _messages[failure]![index < 0 ? 0 : index];
  }

  static const _messages = <PanelDragFailure, List<String>>{
    PanelDragFailure.sourceChanged: [
      'The dragged items changed. Refresh their folder and drag them again.',
      'Die gezogenen Elemente haben sich geändert. Aktualisieren Sie ihren Ordner und ziehen Sie sie erneut.',
      'Les éléments déplacés ont changé. Actualisez leur dossier, puis faites-les glisser à nouveau.',
      'Los elementos arrastrados cambiaron. Actualiza su carpeta y vuelve a arrastrarlos.',
      'Os itens arrastados foram alterados. Atualize a pasta e arraste-os novamente.',
      '拖动的项目已更改。请刷新其文件夹后重新拖动。',
      'ドラッグした項目が変更されました。フォルダーを更新して、もう一度ドラッグしてください。',
      '드래그한 항목이 변경되었습니다. 폴더를 새로 고친 후 다시 드래그하세요.',
      'تغيّرت العناصر المسحوبة. حدّث مجلدها واسحبها مرة أخرى.',
    ],
    PanelDragFailure.destinationChanged: [
      'The destination folder changed. Refresh it and drag the items again.',
      'Der Zielordner hat sich geändert. Aktualisieren Sie ihn und ziehen Sie die Elemente erneut.',
      'Le dossier de destination a changé. Actualisez-le, puis faites glisser les éléments à nouveau.',
      'La carpeta de destino cambió. Actualízala y vuelve a arrastrar los elementos.',
      'A pasta de destino foi alterada. Atualize-a e arraste os itens novamente.',
      '目标文件夹已更改。请刷新后重新拖动项目。',
      '移動先フォルダーが変更されました。更新して、項目をもう一度ドラッグしてください。',
      '대상 폴더가 변경되었습니다. 새로 고친 후 항목을 다시 드래그하세요.',
      'تغيّر مجلد الوجهة. حدّثه واسحب العناصر مرة أخرى.',
    ],
    PanelDragFailure.invalidDestination: [
      'Choose a different folder outside the dragged selection.',
      'Wählen Sie einen anderen Ordner außerhalb der gezogenen Auswahl.',
      'Choisissez un autre dossier en dehors de la sélection déplacée.',
      'Elige otra carpeta fuera de la selección arrastrada.',
      'Escolha outra pasta fora da seleção arrastada.',
      '请选择拖动选区之外的其他文件夹。',
      'ドラッグした選択範囲の外にある別のフォルダーを選んでください。',
      '드래그한 선택 항목 외부의 다른 폴더를 선택하세요.',
      'اختر مجلدًا آخر خارج العناصر المسحوبة.',
    ],
    PanelDragFailure.unavailable: [
      'Could not verify this drop. Reconnect the original storage, refresh the folders, and try again.',
      'Dieses Ablegen konnte nicht geprüft werden. Verbinden Sie den ursprünglichen Speicher erneut, aktualisieren Sie die Ordner und versuchen Sie es erneut.',
      'Impossible de vérifier ce dépôt. Reconnectez le stockage d’origine, actualisez les dossiers et réessayez.',
      'No se pudo verificar este destino. Vuelve a conectar el almacenamiento original, actualiza las carpetas e inténtalo de nuevo.',
      'Não foi possível verificar este destino. Volte a ligar o armazenamento original, atualize as pastas e tente novamente.',
      '无法验证此次拖放。请重新连接原始存储，刷新文件夹后重试。',
      'ドロップを確認できませんでした。元のストレージに再接続し、フォルダーを更新してから再試行してください。',
      '이 드롭을 확인할 수 없습니다. 원래 저장소에 다시 연결하고 폴더를 새로 고친 후 다시 시도하세요.',
      'تعذّر التحقق من الإفلات. أعد الاتصال بوحدة التخزين الأصلية وحدّث المجلدات ثم حاول مرة أخرى.',
    ],
  };
}
