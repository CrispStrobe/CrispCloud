import 'package:quds_office_engine/quds_office_engine.dart';

/// Localized names shared by the review pane, dialog and notes sidebar.
extension WordReviewKindLabel on WmlRevisionKind {
  String reviewLabel({bool arabic = false, bool german = false}) => arabic
      ? switch (this) {
          WmlRevisionKind.insert => 'إدراج',
          WmlRevisionKind.delete => 'حذف',
          WmlRevisionKind.moveFrom => 'نقل من',
          WmlRevisionKind.moveTo => 'نقل إلى',
          WmlRevisionKind.runFormat => 'تنسيق النص',
          WmlRevisionKind.paragraphFormat => 'تنسيق الفقرة',
        }
      : german
      ? switch (this) {
          WmlRevisionKind.insert => 'Eingefügt',
          WmlRevisionKind.delete => 'Gelöscht',
          WmlRevisionKind.moveFrom => 'Verschoben von',
          WmlRevisionKind.moveTo => 'Verschoben nach',
          WmlRevisionKind.runFormat => 'Textformatierung',
          WmlRevisionKind.paragraphFormat => 'Absatzformatierung',
        }
      : label;
}
