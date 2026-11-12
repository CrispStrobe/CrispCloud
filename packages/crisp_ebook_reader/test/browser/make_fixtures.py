"""Self-authored fixtures. All text/artwork in this file is CC0/public domain."""
from pathlib import Path
import sys, zipfile, base64

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aFz8AAAAASUVORK5CYII=')
container = '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
opf = '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:crisp:test</dc:identifier><dc:title>Crisp reader fixture</dc:title><dc:creator>CrispCloud tests</dc:creator><dc:language>en</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="css" href="book.css" media-type="text/css"/><item id="image" href="cover.png" media-type="image/png" properties="cover-image"/><item id="script" href="bad.js" media-type="application/javascript"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>'''
chapter = lambda text: f'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Fixture</title><link rel="stylesheet" href="book.css"/></head><body>{text}</body></html>'
one = chapter('''<h1 id="start">The blue library</h1><p>Library lanterns illuminate café shelves. <strong>Books stay local.</strong></p><p><a href="two.xhtml#finish">Visit the second chapter.</a></p><img src="cover.png" alt="Tiny fixture"/><script>parent.__bookScriptRan = true</script><script src="bad.js"></script><img src="https://invalid.example.test/tracker" onerror="parent.__bookScriptRan = true"/><iframe src="https://invalid.example.test/frame"/><p>''' + 'A library has a thousand stories. ' * 700 + '</p>')
two = chapter('<h1 id="finish">A second shelf</h1><p>The library journey continues here. Ελληνικά 日本語 café.</p>')
nav = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="one.xhtml#start">The blue library</a><ol><li><a href="two.xhtml#finish">Second shelf</a></li></ol></li></ol></nav></body></html>'
for encrypted in [False, True]:
    with zipfile.ZipFile(out / ('encrypted.epub' if encrypted else 'fixture.epub'),'w') as z:
        z.writestr('mimetype','application/epub+zip',compress_type=zipfile.ZIP_STORED)
        for path, data in {'META-INF/container.xml':container,'OPS/book.opf':opf,'OPS/one.xhtml':one,'OPS/two.xhtml':two,'OPS/nav.xhtml':nav,'OPS/book.css':'body { font-family:serif; } h1 { color:#285b87; }','OPS/cover.png':png,'OPS/bad.js':'parent.__bookScriptRan = true'}.items():
            z.writestr(path,data,compress_type=zipfile.ZIP_DEFLATED)
        if encrypted: z.writestr('META-INF/encryption.xml','<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/><CipherData><CipherReference URI="OPS/one.xhtml"/></CipherData></EncryptedData></encryption>')
with zipfile.ZipFile(out/'fixture.cbz','w') as z:
    z.writestr('page-1.png',png)
    z.writestr('page-2.png',png)
fb2 = f'''<?xml version="1.0" encoding="utf-8"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><genre>prose</genre><author><first-name>Crisp</first-name><last-name>Tests</last-name></author><book-title>FB2 local fixture</book-title><lang>en</lang></title-info><document-info><id>crisp-fb2-fixture</id></document-info></description><body><section id="one"><title><p>First chapter</p></title><p>A library is a good place to read.</p><image l:href="#picture"/><p><a l:href="#two">Continue</a></p></section><section id="two"><title><p>Second chapter</p></title><p>Another library shelf.</p></section></body><binary id="picture" content-type="image/png">{base64.b64encode(png).decode()}</binary></FictionBook>'''
(out/'fixture.fb2').write_text(fb2,encoding='utf8')
print(out)
