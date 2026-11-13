// SPDX-License-Identifier: MIT
// Exact, bounded app-asset descriptors for isolated document rendering.
import '../models.dart';

const documentPreviewMaxFonts = 64;
const documentPreviewMaxFontAliases = 16;
const documentPreviewMaxFontFamilyLength = 128;
final _fontNameControls = RegExp(r'[\x00-\x1f\x7f]');
final _invalidFontPathPart = RegExp(r'[^A-Za-z0-9_.-]');

bool isDocumentPreviewFontAsset(String asset) {
  if (asset.length > 512) return false;
  final parts = asset.split('/');
  return parts.length >= 2 &&
      const {'assets', 'packages'}.contains(parts.first) &&
      parts.every(
        (part) =>
            part.isNotEmpty &&
            part != '.' &&
            part != '..' &&
            !_invalidFontPathPart.hasMatch(part),
      ) &&
      documentFontAssetContentType(asset) != null;
}

String? documentFontAssetContentType(String asset) =>
    switch (asset.split('.').last.toLowerCase()) {
      'ttf' => 'font/ttf',
      'otf' => 'font/otf',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      _ => null,
    };

bool _validFamily(String family) =>
    family.isNotEmpty &&
    family.length <= documentPreviewMaxFontFamilyLength &&
    family.trim() == family &&
    !_fontNameControls.hasMatch(family);

/// Snapshot trusted configuration before crossing an asynchronous host boundary.
/// Neither document content nor a JS message can add font assets to this list.
List<DocumentPreviewFont> snapshotDocumentPreviewFonts(
  List<DocumentPreviewFont> fonts,
) {
  if (fonts.length > documentPreviewMaxFonts) {
    throw ArgumentError('Too many document preview font faces.');
  }
  final styles = <(String, int, bool)>{};
  final result = <DocumentPreviewFont>[];
  for (final font in fonts) {
    if (!isDocumentPreviewFontAsset(font.asset) ||
        !_validFamily(font.family) ||
        font.aliases.length > documentPreviewMaxFontAliases ||
        !font.aliases.every(_validFamily) ||
        font.weight < 100 ||
        font.weight > 900 ||
        font.weight % 100 != 0 ||
        !styles.add((font.family.toLowerCase(), font.weight, font.italic))) {
      throw ArgumentError('Invalid document preview font descriptor.');
    }
    result.add(
      DocumentPreviewFont(
        asset: font.asset,
        family: font.family,
        aliases: List.unmodifiable(font.aliases),
        weight: font.weight,
        italic: font.italic,
      ),
    );
  }
  return List.unmodifiable(result);
}

DocumentJson documentHostFontDescriptor(DocumentPreviewFont font, Uri url) => {
  'family': font.family,
  'aliases': font.aliases,
  'weight': font.weight,
  'italic': font.italic,
  'url': url.toString(),
};

/// Flutter's web asset layout retains the embedding application's base path.
/// The asset key grammar excludes origins, traversal, queries and escapes.
List<DocumentJson> documentWebFontDescriptors(
  Uri appBase,
  List<DocumentPreviewFont> fonts,
) {
  if (!const {'http', 'https'}.contains(appBase.scheme) ||
      !appBase.hasAuthority ||
      appBase.userInfo.isNotEmpty) {
    throw ArgumentError('Invalid document application base URL.');
  }
  final checked = snapshotDocumentPreviewFonts(fonts);
  return [
    for (final font in checked)
      documentHostFontDescriptor(font, appBase.resolve('assets/${font.asset}')),
  ];
}

/// Font URLs are provided only by the host, and only with a new document.
DocumentJson documentHostMessageWithFonts(
  DocumentJson message,
  List<DocumentJson> fonts,
) => message['type'] == 'begin' ? {...message, 'fonts': fonts} : message;
