import 'package:flutter/widgets.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import 'image_editor_translations.dart';

/// One catalog for CrispCloud chrome and every reachable engine string.
///
/// Supported locales never fall through to an English package default.
/// The source coverage test fails when the fork gains a visible I18n field
/// without an explicit host mapping. Emoji, sticker, audio and video tools
/// are disabled by the host and are intentionally outside this surface.
abstract final class ImageEditorStrings {
  static const catalog = imageEditorTranslations;
  static const supportedLanguageCodes = <String>{
    'en',
    'de',
    'fr',
    'es',
    'pt',
    'zh',
    'ja',
    'ko',
    'ar',
  };

  static String translate(BuildContext context, String english) =>
      forLanguage(Localizations.localeOf(context).languageCode, english);

  static String forLanguage(String languageCode, String english) {
    final table = catalog[languageCode] ?? catalog['en']!;
    final value = table[english];
    if (value == null) {
      throw StateError(
        'Missing image editor translation: $languageCode / $english',
      );
    }
    return value;
  }

  static I18n editorI18n(BuildContext context) =>
      editorI18nForLocale(Localizations.localeOf(context));

  static I18n editorI18nForLocale(Locale locale) =>
      _main((english) => forLanguage(locale.languageCode, english));

  static I18n _main(String Function(String) t) {
    return I18n(
      various: _various(t),
      layerInteraction: _layerInteraction(t),
      paintEditor: _paintEditor(t),
      textEditor: _textEditor(t),
      cropRotateEditor: _cropRotateEditor(t),
      tuneEditor: _tuneEditor(t),
      filterEditor: _filterEditor(t),
      blurEditor: _blurEditor(t),
      importStateHistoryMsg: t('Loading image…'),
      cancel: t('Cancel'),
      undo: t('Undo'),
      redo: t('Redo'),
      done: t('Apply'),
      remove: t('Remove'),
      doneLoadingMsg: t('Applying changes…'),
    );
  }

  static I18nVarious _various(String Function(String) t) {
    return I18nVarious(
      loadingDialogMsg: t('Loading image…'),
      closeEditorWarningTitle: t('Close image editor?'),
      closeEditorWarningMessage: t('Unsaved changes will be lost.'),
      closeEditorWarningConfirmBtn: t('Discard'),
      closeEditorWarningCancelBtn: t('Cancel'),
    );
  }

  static I18nLayerInteraction _layerInteraction(String Function(String) t) {
    return I18nLayerInteraction(
      remove: t('Remove'),
      edit: t('Edit'),
      rotateScale: t('Rotate and scale'),
    );
  }

  static I18nPaintEditor _paintEditor(String Function(String) t) {
    return I18nPaintEditor(
      moveAndZoom: t('Zoom'),
      bottomNavigationBarText: t('Draw'),
      freestyle: t('Freestyle'),
      freestyleArrowStart: t('Freestyle arrow start'),
      freestyleArrowEnd: t('Freestyle arrow end'),
      freestyleArrowStartEnd: t('Freestyle arrow start-end'),
      arrow: t('Arrow'),
      line: t('Line'),
      rectangle: t('Rectangle'),
      circle: t('Circle'),
      dashLine: t('Dash line'),
      dashDotLine: t('Dash-dot line'),
      hexagon: t('Hexagon'),
      polygon: t('Polygon'),
      blur: t('Blur'),
      pixelate: t('Pixelate'),
      custom1: t('Custom 1'),
      custom2: t('Custom 2'),
      custom3: t('Custom 3'),
      lineWidth: t('Line width'),
      eraser: t('Eraser'),
      toggleFill: t('Toggle fill'),
      changeOpacity: t('Change opacity'),
      undo: t('Undo'),
      redo: t('Redo'),
      done: t('Apply'),
      back: t('Back'),
      smallScreenMoreTooltip: t('More'),
      opacity: t('Opacity'),
      color: t('Color'),
      strokeWidth: t('Stroke width'),
      fill: t('Fill'),
      cancel: t('Cancel'),
    );
  }

  static I18nTextEditor _textEditor(String Function(String) t) {
    return I18nTextEditor(
      inputHintText: t('Enter text'),
      fontFamilyExampleText: t('Aa'),
      bottomNavigationBarText: t('Text'),
      back: t('Back'),
      cancel: t('Cancel'),
      reset: t('Reset'),
      done: t('Apply'),
      textAlign: t('Align text'),
      fontScale: t('Font scale'),
      backgroundMode: t('Background mode'),
      smallScreenMoreTooltip: t('More'),
    );
  }

  static I18nCropRotateEditor _cropRotateEditor(String Function(String) t) {
    return I18nCropRotateEditor(
      bottomNavigationBarText: t('Crop and rotate'),
      rotate: t('Rotate'),
      flip: t('Flip'),
      tilt: t('Tilt'),
      tiltRotate: t('Rotate'),
      tiltHorizontal: t('Horizontal'),
      tiltVertical: t('Vertical'),
      ratio: t('Ratio'),
      back: t('Back'),
      done: t('Apply'),
      cancel: t('Cancel'),
      undo: t('Undo'),
      redo: t('Redo'),
      smallScreenMoreTooltip: t('More'),
      reset: t('Reset'),
    );
  }

  static I18nTuneEditor _tuneEditor(String Function(String) t) {
    return I18nTuneEditor(
      bottomNavigationBarText: t('Adjust'),
      back: t('Back'),
      done: t('Apply'),
      brightness: t('Brightness'),
      contrast: t('Contrast'),
      saturation: t('Saturation'),
      exposure: t('Exposure'),
      hue: t('Hue'),
      temperature: t('Temperature'),
      fade: t('Fade'),
      tint: t('Tint'),
      undo: t('Undo'),
      redo: t('Redo'),
    );
  }

  static I18nFilterEditor _filterEditor(String Function(String) t) {
    return I18nFilterEditor(
      filters: _filters(t),
      bottomNavigationBarText: t('Filters'),
      back: t('Back'),
      done: t('Apply'),
    );
  }

  static I18nFilters _filters(String Function(String) t) {
    return I18nFilters(
      none: t('No filter'),
      addictiveBlue: t('Addictive blue'),
      addictiveRed: t('Addictive red'),
      aden: t('Aden'),
      amaro: t('Amaro'),
      ashby: t('Ashby'),
      brannan: t('Brannan'),
      brooklyn: t('Brooklyn'),
      charmes: t('Charmes'),
      clarendon: t('Clarendon'),
      crema: t('Crema'),
      dogpatch: t('Dogpatch'),
      earlybird: t('Earlybird'),
      f1977: t('1977'),
      gingham: t('Gingham'),
      ginza: t('Ginza'),
      hefe: t('Hefe'),
      helena: t('Helena'),
      hudson: t('Hudson'),
      inkwell: t('Inkwell'),
      juno: t('Juno'),
      kelvin: t('Kelvin'),
      lark: t('Lark'),
      loFi: t('Lo-Fi'),
      ludwig: t('Ludwig'),
      maven: t('Maven'),
      mayfair: t('Mayfair'),
      moon: t('Moon'),
      nashville: t('Nashville'),
      perpetua: t('Perpetua'),
      reyes: t('Reyes'),
      rise: t('Rise'),
      sierra: t('Sierra'),
      skyline: t('Skyline'),
      slumber: t('Slumber'),
      stinson: t('Stinson'),
      sutro: t('Sutro'),
      toaster: t('Toaster'),
      valencia: t('Valencia'),
      vesper: t('Vesper'),
      walden: t('Walden'),
      willow: t('Willow'),
      xProII: t('X-Pro II'),
    );
  }

  static I18nBlurEditor _blurEditor(String Function(String) t) {
    return I18nBlurEditor(
      bottomNavigationBarText: t('Blur'),
      back: t('Back'),
      done: t('Apply'),
    );
  }
}

extension ImageEditorTranslation on BuildContext {
  String imageTr(String english) => ImageEditorStrings.translate(this, english);
}
