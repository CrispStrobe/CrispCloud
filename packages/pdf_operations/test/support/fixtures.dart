import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

Uint8List workflowPdf({String label = 'Source', int pageCount = 3}) {
  final document =
      PdfDocument.open(PdfBlankDocument.create(pageCount: pageCount));
  final editor = PdfEditor(document);
  for (var page = 0; page < pageCount; page++) {
    editor.stampPage(
        page,
        (stamp) =>
            stamp.text('$label page ${page + 1}', x: 72, y: 720, size: 18));
    editor.addOutlineItem('$label chapter ${page + 1}', pageIndex: page);
  }
  final name =
      editor.addTextField(0, 'customer.name', const PdfRect(72, 620, 400, 650));
  editor.setTextValue(name, 'Original');
  editor.addCheckBoxField(0, 'agree', const PdfRect(72, 580, 92, 600));
  editor.addComboBoxField(0, 'delivery', const PdfRect(72, 530, 230, 560),
      [('standard', 'Standard'), ('express', 'Express')]);
  editor.addListBoxField(0, 'interests', const PdfRect(250, 500, 450, 600),
      [('books', 'Books'), ('music', 'Music'), ('art', 'Art')],
      multiSelect: true);
  editor.addRadioGroup(0, 'color', [
    (const PdfRect(72, 460, 92, 480), 'Red'),
    (const PdfRect(120, 460, 140, 480), 'Blue'),
  ]);
  editor.addNote(0, 480, 600, 'Keep this existing comment',
      name: 'existing-comment');
  if (pageCount > 1) {
    final second =
        editor.addTextField(1, 'second', const PdfRect(72, 600, 300, 630));
    editor.setTextValue(second, 'Second page field');
    editor.addLinkToPage(0, [const PdfRect(72, 680, 240, 700)], targetPage: 1);
  }
  return editor.save();
}

/// Four rotated pages with a nonzero crop origin and two different sizes.
Uint8List geometryPdf() {
  final document = PdfDocument.open(PdfBlankDocument.create(pageCount: 4));
  final updater = CosIncrementalUpdater(document.cos);
  for (var i = 0; i < 4; i++) {
    final page = document.page(i);
    final right = i < 2 ? 330 : 430;
    page.dict['CropBox'] = CosArray([
      const CosInteger(30),
      const CosInteger(40),
      CosInteger(right),
      const CosInteger(440),
    ]);
    page.dict['Rotate'] = CosInteger(i * 90);
    updater.markChanged(page.dict);
  }
  return updater.save();
}

Uint8List restrictedFormPdf() {
  final document = PdfDocument.open(workflowPdf());
  final editor = PdfEditor(document);
  final password =
      editor.addTextField(0, 'password', const PdfRect(72, 370, 250, 400));
  password.dict['Ff'] = const CosInteger(PdfFormField.passwordFlag);
  editor.setTextValue(password, 'historical-test-password');
  final limited =
      editor.addTextField(0, 'short', const PdfRect(72, 320, 250, 350));
  limited.dict['MaxLen'] = const CosInteger(3);
  editor.setTextValue(limited, 'old');
  final readOnly =
      editor.addTextField(0, 'readOnly', const PdfRect(72, 270, 250, 300));
  editor.setTextValue(readOnly, 'fixed');
  readOnly.dict['Ff'] = const CosInteger(PdfFormField.readOnlyFlag);
  final required =
      editor.addTextField(0, 'required', const PdfRect(72, 220, 250, 250));
  required.dict['Ff'] = const CosInteger(PdfFormField.requiredFlag);
  editor.setTextValue(required, 'present');
  return editor.save();
}

/// A legitimate simple-font remapping: byte 66 displays the glyph "eight".
/// A Latin-1-only form writer must not silently use it to write the letter B.
Uint8List remappedFormPdf() {
  final document = PdfDocument.open(workflowPdf());
  final form = PdfAcroForm.of(document)!;
  final fonts =
      document.cos.resolve(form.defaultResources!['Font']) as CosDictionary;
  final font = document.cos.resolve(fonts['Helv']) as CosDictionary;
  font['Encoding'] = CosDictionary({
    'BaseEncoding': const CosName('WinAnsiEncoding'),
    'Differences': CosArray([const CosInteger(66), const CosName('eight')]),
  });
  final updater = CosIncrementalUpdater(document.cos)..markChanged(font);
  return updater.save();
}

/// A signature-schema marker, not a cryptographically valid signing fixture.
Uint8List signatureMarkerPdf() {
  final document = PdfDocument.open(PdfBlankDocument.create());
  final updater = CosIncrementalUpdater(document.cos);
  final signature = updater.addObject(CosDictionary({
    'Type': const CosName('Sig'),
    'Filter': const CosName('Adobe.PPKLite'),
    'SubFilter': const CosName('adbe.pkcs7.detached'),
    'ByteRange': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(0)
    ]),
    'Contents': CosString(Uint8List(1), isHex: true),
  }));
  final field = updater.addObject(CosDictionary({
    'FT': const CosName('Sig'),
    'T': CosString.fromText('signature'),
    'V': signature,
  }));
  document.catalog['AcroForm'] = CosDictionary({
    'Fields': CosArray([field])
  });
  updater.markChanged(document.catalog);
  return updater.save();
}

Uint8List redLogoPng() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABQAAAAKCAIAAAA7N+mxAAAAF0lEQVR4nGN8pmHEQC5gIlvnqOYRoxkAExcBVABjfAkAAAAASUVORK5CYII=');
