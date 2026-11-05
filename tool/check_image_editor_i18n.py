#!/usr/bin/env python3
"""Check the image editor catalog against its fork's visible string fields.

No Flutter runtime is needed. Run from any directory with:
    python3 tool/check_image_editor_i18n.py

An upstream I18n field addition must fail this gate until the host explicitly
maps it. Locale tables must contain the same nonempty keys, and visible host
lookups must resolve in every supported language.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {"en", "de", "fr", "es", "pt", "zh", "ja", "ko", "ar"}
VISIBLE_CLASSES = {
    "I18n", "I18nVarious", "I18nLayerInteraction", "I18nPaintEditor",
    "I18nTextEditor", "I18nCropRotateEditor", "I18nTuneEditor",
    "I18nFilterEditor", "I18nFilters", "I18nBlurEditor",
}
DISABLED_CLASSES = {
    "I18nEmojiEditor", "I18nStickerEditor", "I18nAudioEditor", "I18nClipsEditor",
}
DART_STRING = r"'(?:\\.|[^'\\])*'"


def unquote(value: str) -> str:
    escapes = {"n": "\n", "r": "\r", "t": "\t", "'": "'", "\\": "\\", "$": "$"}
    return re.sub(r"\\(.)", lambda match: escapes[match[1]], value[1:-1])


def block(source: str, start: int, opening: str = "{") -> str:
    """Read a balanced Dart block, ignoring brackets inside string literals."""
    closing = {"{": "}", "(": ")"}[opening]
    depth = 0
    quote = None
    escaped = False
    for index in range(start, len(source)):
        char = source[index]
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in "'\"":
            quote = char
        elif char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return source[start + 1:index]
    raise ValueError("Unterminated Dart block")


def string_map(source: str) -> dict[str, str]:
    result = {}
    for match in re.finditer(rf"({DART_STRING})\s*:\s*({DART_STRING})", source):
        key, value = unquote(match[1]), unquote(match[2])
        if key in result:
            raise ValueError(f"Duplicate translation key: {key}")
        if not value.strip():
            raise ValueError(f"Empty translation: {key}")
        result[key] = value
    return result


def literal_arguments(source: str, names: str) -> set[str]:
    result = set()
    for match in re.finditer(rf"\b(?:{names})\(", source):
        arguments = block(source, match.end() - 1, "(")
        result.update(unquote(value[0]) for value in re.finditer(DART_STRING, arguments))
    return result


def check() -> tuple[int, int]:
    strings = (ROOT / "lib/l10n/image_editor_strings.dart").read_text()
    translations = (ROOT / "lib/l10n/image_editor_translations.dart").read_text()
    named_start = translations.index("{", translations.index("imageEditorInvariantFilterNames"))
    invariant = string_map(block(translations, named_start))
    catalog = {}
    for match in re.finditer(r"^  '(\w+)': <String, String>\{", translations, re.M):
        body = block(translations, match.end() - 1)
        table = string_map(body)
        if "...imageEditorInvariantFilterNames" in body:
            table = {**invariant, **table}
        catalog[match[1]] = table
    if catalog.keys() != LANGUAGES:
        raise ValueError(f"Locale coverage changed: {sorted(catalog)}")
    keys = catalog["en"].keys()
    for language, table in catalog.items():
        if table.keys() != keys:
            raise ValueError(
                f"{language}: missing={sorted(keys - table.keys())}, "
                f"unexpected={sorted(table.keys() - keys)}"
            )

    package = ROOT / "packages/pro_image_editor/lib/core/models/i18n"
    class_sources = {}
    for path in package.glob("*.dart"):
        # Strip documentation so sample declarations never count as API fields.
        source = re.sub(r"^\s*//.*$", "", path.read_text(), flags=re.M)
        for match in re.finditer(r"^class (I18n\w*)\s*\{", source, re.M):
            class_sources[match[1]] = block(source, match.end() - 1)
    field_count = 0
    for class_name in sorted(VISIBLE_CLASSES):
        body = class_sources[class_name]
        fields = set(re.findall(r"final String\?? (\w+);", body))
        constructor = re.search(rf"\breturn {class_name}\(", strings)
        if constructor is None:
            raise ValueError(f"No host mapping for {class_name}")
        arguments = block(strings, constructor.end() - 1, "(")
        mapped = set(re.findall(r"^\s*(\w+):\s*t\(", arguments, re.M))
        if fields != mapped:
            raise ValueError(
                f"{class_name}: missing={sorted(fields - mapped)}, "
                f"unexpected={sorted(mapped - fields)}"
            )
        field_count += len(fields)
    for nested in re.findall(r"final (I18n\w+) \w+;", class_sources["I18n"]):
        if nested not in VISIBLE_CLASSES | DISABLED_CLASSES:
            raise ValueError(f"New editor component requires localization review: {nested}")

    lookups = set()
    for match in re.finditer(rf"\bt\(\s*({DART_STRING})", strings):
        lookups.add(unquote(match[1]))
    paths = [
        "lib/widgets/image_editor_dialog.dart",
        "lib/widgets/image_editor_surface.dart",
        "lib/widgets/image_editor_menus.dart",
        "lib/widgets/file_editor_dialog.dart",
        "lib/widgets/file_context_menu.dart",
        "lib/screens/file_browser_screen.dart",
    ]
    for name in paths:
        path = ROOT / name
        if not path.exists():
            raise ValueError(f"Missing host source: {name}")
        source = path.read_text()
        # Includes conditional keys such as imageTr(saving ? 'Saving…' : 'Save').
        lookups.update(literal_arguments(source, "imageTr"))
        if name.endswith("image_editor_menus.dart"):
            lookups.update(literal_arguments(source, "item"))
        if name.endswith("image_editor_dialog.dart"):
            lookups.update(literal_arguments(source, "_showMessage|_messageFor|_ImageOpenMessage"))
            for match in re.finditer(rf"\(ImageEditorAction\.\w+,\s*({DART_STRING})", source):
                lookups.add(unquote(match[1]))
            error_switch = re.search(r"String _messageFor\([^)]*\)\s*=>\s*switch[^{]*\{", source)
            if error_switch is not None:
                body = block(source, error_switch.end() - 1)
                lookups.update(unquote(value[0]) for value in re.finditer(DART_STRING, body))
    if not lookups <= keys:
        raise ValueError(f"Missing visible strings: {sorted(lookups - keys)}")
    return len(keys), field_count


if __name__ == "__main__":
    try:
        key_count, field_count = check()
    except (ValueError, KeyError) as error:
        print(f"Image editor localization check failed: {error}", file=sys.stderr)
        raise SystemExit(1)
    print(
        f"Image editor localization: {len(LANGUAGES)} complete locales, "
        f"{key_count} keys each, {field_count} explicitly mapped package strings."
    )
