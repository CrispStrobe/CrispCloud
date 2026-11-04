/// People templates: letter and certificate.
library;

import 'dart:typed_data';

import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_types.dart';
import 'kit.dart';
import 'sheets.dart';

/// Letter labels. Body text lives on the template, not here.
class LetterLabels {
  /// LetterLabels API.
  const LetterLabels({
    this.document = 'Letter',
    this.to = 'To',
    this.subject = 'Subject',
    this.closing = 'Yours sincerely',
  });

  /// document API.
  final String document;

  /// to API.
  final String to;

  /// subject API.
  final String subject;

  /// closing API.
  final String closing;
}

/// Formal letter. Paragraphs are caller text in either language.
class LetterTemplate {
  /// LetterTemplate API.
  LetterTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.people,
    this.font,
    this.fontBold,
    required this.sender,
    required this.recipient,
    required this.subject,
    this.paragraphs = const <String>[],
    this.labels = const LetterLabels(),
    this.date = '',
    this.reference = '',
    this.sign,
    this.footer = '',
  });

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// sender API.
  final TemplateParty sender;

  /// recipient API.
  final TemplateParty recipient;

  /// subject API.
  final String subject;

  /// paragraphs API.
  final List<String> paragraphs;

  /// labels API.
  final LetterLabels labels;

  /// date API.
  final String date;

  /// reference API.
  final String reference;

  /// sign API.
  final SignSlot? sign;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    final SignSlot? slot = sign;
    return SheetTemplate(
      kind: SheetKind.letter,
      skin: SheetSkin.letter,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: sender,
      other: recipient,
      labels: SheetLabels(
        document: labels.document,
        to: labels.to,
        extra: reference,
      ),
      date: date,
      extra: reference,
      subject: subject,
      paragraphs: paragraphs,
      notes: labels.closing,
      footer: footer.isEmpty ? sender.name : footer,
      signs: slot == null ? const <SignSlot>[] : <SignSlot>[slot],
    ).save();
  }
}

/// Certificate labels.
class CertificateLabels {
  /// CertificateLabels API.
  const CertificateLabels({
    this.document = 'Certificate',
    this.presentedTo = 'Presented to',
    this.date = 'Date',
  });

  /// document API.
  final String document;

  /// presentedTo API.
  final String presentedTo;

  /// date API.
  final String date;
}

/// Landscape certificate. Body is one paragraph the caller writes.
class CertificateTemplate {
  /// CertificateTemplate API.
  CertificateTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.people,
    this.font,
    this.fontBold,
    required this.issuer,
    required this.recipient,
    required this.award,
    this.body = '',
    this.labels = const CertificateLabels(),
    this.date = '',
    this.signs = const <SignSlot>[],
    this.footer = '',
  });

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// issuer API.
  final TemplateParty issuer;

  /// recipient API.
  final String recipient;

  /// award API.
  final String award;

  /// body API.
  final String body;

  /// labels API.
  final CertificateLabels labels;

  /// date API.
  final String date;

  /// signs API.
  final List<SignSlot> signs;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.award,
      skin: SheetSkin.certificate,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: issuer,
      labels: SheetLabels(
        document: labels.document,
        presentedTo: labels.presentedTo,
        date: labels.date,
      ),
      recipient: recipient,
      subject: award,
      date: date,
      paragraphs: body.isEmpty ? const <String>[] : <String>[body],
      footer: footer.isEmpty ? issuer.name : footer,
      signs: signs,
      landscape: true,
    ).save();
  }
}
