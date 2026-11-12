"""Prepare a standalone Flutter/Linux host test, independent of the app build."""
from pathlib import Path
import argparse
import json
import shutil
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("--portable-only", action="store_true")
args = parser.parse_args()
package = Path(__file__).resolve().parents[1]
output = args.output.resolve()
if not (output / "linux/CMakeLists.txt").is_file():
    raise SystemExit("Create the Linux Flutter project before preparing its test.")

(output / "pubspec.yaml").write_text(f"""name: crisp_linux_host_smoke
publish_to: none
environment:
  sdk: '>=3.6.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  crisp_ebook_reader:
    path: {json.dumps(str(package))}
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
flutter:
  uses-material-design: true
  assets:
    - assets/host-smoke.epub
""", encoding="utf-8")
for directory in ["assets", "integration_test", "tool", "lib"]:
    (output / directory).mkdir(exist_ok=True)
shutil.copyfile(package / "test/linux/reader_host_integration.dart",
                output / "integration_test/reader_host_test.dart")
shutil.copyfile(package / "tool/capture_linux_host.py", output / "tool/capture_linux_host.py")
(output / "lib/runtime_probe.dart").write_text('''import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = await probeEbookLinuxHost();
  stdout.writeln(jsonEncode({
    'available': status.available,
    'runtime': status.runtime,
    'reason': status.reason,
  }));
  exit(!status.available && status.reason != null ? 0 : 1);
}
''', encoding="utf-8")

# Self-authored fixture, CC0. The green rectangle is a pixel-level proof that the
# actual WebKit texture reached the X11 window; Flutter paints a magenta overlay.
container = '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
opf = '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:crisp:linux-host-smoke</dc:identifier><dc:title>Linux inline library</dc:title><dc:creator>CrispCloud tests</dc:creator><dc:language>en</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>'''
chapter = lambda body: '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Library</title></head><body>' + body + '</body></html>'
hostile = '''<script>fetch('http://127.0.0.1:18189/script')</script><img src="http://127.0.0.1:18189/image" alt=""/><iframe src="http://127.0.0.1:18189/frame"></iframe><style>body { background-image: url('http://127.0.0.1:18189/style'); }</style>'''
one = chapter('<h1 id="start">Library lanterns</h1><p>Library lanterns illuminate café shelves. Books stay local.</p><svg xmlns="http://www.w3.org/2000/svg" width="80" height="40" viewBox="0 0 80 40"><rect width="80" height="40" fill="#1f5947"/></svg>' + hostile + ''.join(f'<p>Library paragraph {i}. A thousand stories stay on these local shelves.</p>' for i in range(100)))
two = chapter('<h1 id="finish">Second library shelf</h1><p>The journey continues. Ελληνικά 日本語 café.</p><p><a href="one.xhtml#start">Return to the first chapter</a></p><p><a href="#finish">Stay in this chapter</a></p>')
nav = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="one.xhtml#start">Library lanterns</a></li><li><a href="two.xhtml#finish">Second library shelf</a></li></ol></nav></body></html>'
with zipfile.ZipFile(output / "assets/host-smoke.epub", "w") as archive:
    archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    for name, text in {"META-INF/container.xml": container, "OPS/book.opf": opf,
                       "OPS/one.xhtml": one, "OPS/two.xhtml": two, "OPS/nav.xhtml": nav}.items():
        archive.writestr(name, text, compress_type=zipfile.ZIP_DEFLATED)

if args.portable_only:
    cmake = output / "linux/CMakeLists.txt"
    source = cmake.read_text(encoding="utf-8")
    needle = "include(flutter/generated_plugins.cmake)"
    if needle not in source:
        raise SystemExit("Cannot locate the generated plugin inclusion in Linux CMake.")
    cmake.write_text(source.replace(needle, 'set(CRISP_EBOOK_WEBKITGTK OFF CACHE BOOL "" FORCE)\n' + needle), encoding="utf-8")
print(output)
