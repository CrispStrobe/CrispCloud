import 'package:quds_office_engine/quds_office_engine.dart';

/// Hosts an isolated child package (sheet-in-word, word-in-sheet, …).
class EmbeddedObjectHost {
  /// EmbeddedObjectHost API.
  EmbeddedObjectHost(this.embedded);

  /// embedded API.
  IsolatedEmbeddedPackage embedded;

  /// asWorkbook API.
  SmlWorkbook? asWorkbook() {
    if (embedded.kind != OpcPackageKind.sheet) {
      return null;
    }
    return SheetDeserializer().read(embedded.package);
  }

  /// asDocument API.
  WmlDocument? asDocument() {
    if (embedded.kind != OpcPackageKind.word) {
      return null;
    }
    return WordDeserializer().read(embedded.package);
  }

  /// asPresentation API.
  PmlPresentation? asPresentation() {
    if (embedded.kind != OpcPackageKind.slide) {
      return null;
    }
    return SlideDeserializer().read(embedded.package);
  }

  /// Writes mutated child bytes back into the OLE package.
  void commitChild() {
    embedded = IsolatedEmbeddedPackage(
      package: embedded.package,
      kind: embedded.kind,
      displayName: embedded.displayName,
      thumbnail: embedded.thumbnail,
      progId: embedded.progId,
    );
  }
}
