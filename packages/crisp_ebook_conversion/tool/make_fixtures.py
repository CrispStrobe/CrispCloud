"""Generate original, deterministic MIT-licensed ebook test fixtures."""
from pathlib import Path
import struct
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]


def png(width=500, height=750):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = (b"\0" + b"\x30\x70\xa0" * width) * height
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows))
            + chunk(b"IEND", b""))


def contents():
    return {
        "mimetype": "application/epub+zip",
        "META-INF/container.xml": """<?xml version="1.0" encoding="UTF-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles>
<rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""",
        "OEBPS/package.opf": """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bookid">urn:uuid:88888888-1234-4321-abcd-123456789012</dc:identifier>
<dc:title>Crisp Conversion Fixture</dc:title><dc:creator>Test Author</dc:creator>
<dc:language>en</dc:language><meta property="dcterms:modified">2026-11-12T00:00:00Z</meta>
<meta name="cover" content="cover-image"/></metadata>
<manifest>
<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
<item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="css" href="style.css" media-type="text/css"/>
<item id="cover-image" href="cover.png" properties="cover-image" media-type="image/png"/>
</manifest><spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine></package>""",
        "OEBPS/chapter1.xhtml": """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en"><head>
<title>First Chapter</title><link rel="stylesheet" href="style.css"/></head><body>
<h1 id="first">First Chapter</h1><p>The silver heron visits CrispCloud.</p>
<p>Unicode: café, Ωμέγα, 日本語.</p><img src="cover.png" alt="Original blue test cover"/>
<p id="answer">The answer is forty-two.</p>
<p><a href="chapter2.xhtml#second">Continue to the second chapter</a>.</p></body></html>""",
        "OEBPS/chapter2.xhtml": """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en"><head>
<title>Second Chapter</title><link rel="stylesheet" href="style.css"/></head><body>
<h1 id="second">Second Chapter</h1>
<p><a href="chapter1.xhtml#answer">Return to the answer</a>.</p></body></html>""",
        "OEBPS/nav.xhtml": """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head>
<title>Contents</title></head><body><nav epub:type="toc" id="toc"><h1>Contents</h1><ol>
<li><a href="chapter1.xhtml#first">First Chapter</a><ol>
<li><a href="chapter1.xhtml#answer">The Answer</a></li></ol></li>
<li><a href="chapter2.xhtml#second">Second Chapter</a></li></ol></nav></body></html>""",
        "OEBPS/toc.ncx": """<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head>
<meta name="dtb:uid" content="urn:uuid:88888888-1234-4321-abcd-123456789012"/>
<meta name="dtb:depth" content="2"/><meta name="dtb:totalPageCount" content="0"/>
<meta name="dtb:maxPageNumber" content="0"/></head><docTitle><text>Crisp Conversion Fixture</text></docTitle>
<navMap><navPoint id="n1" playOrder="1"><navLabel><text>First Chapter</text></navLabel>
<content src="chapter1.xhtml#first"/><navPoint id="n2" playOrder="2"><navLabel><text>The Answer</text></navLabel>
<content src="chapter1.xhtml#answer"/></navPoint></navPoint>
<navPoint id="n3" playOrder="3"><navLabel><text>Second Chapter</text></navLabel>
<content src="chapter2.xhtml#second"/></navPoint></navMap></ncx>""",
        "OEBPS/style.css": "body { color: #234; } h1 { font-weight: bold; } p { margin: 0.5em 0; }",
        "OEBPS/cover.png": png(),
    }


def write(path, files):
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo(name, (2026, 11, 12, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
            info.external_attr = 0o100600 << 16
            archive.writestr(info, data)


if __name__ == "__main__":
    target = ROOT / "test/fixtures"
    target.mkdir(parents=True, exist_ok=True)
    write(target / "book.epub", contents())
    files = contents()
    files["../escape.txt"] = "must never be extracted"
    write(target / "traversal.epub", files)
    files = contents()
    files["OEBPS/chapter1.xhtml"] = files["OEBPS/chapter1.xhtml"].replace('src="cover.png"', 'src="../../../../private.png"')
    write(target / "external_resource.epub", files)
    files = contents()
    files["META-INF/encryption.xml"] = """<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/>
<CipherData><CipherReference URI="OEBPS/chapter1.xhtml"/></CipherData></EncryptedData></encryption>"""
    write(target / "protected.epub", files)
    print(f"Generated four original fixtures in {target}")

