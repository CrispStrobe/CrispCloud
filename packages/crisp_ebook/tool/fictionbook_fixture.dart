import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:path/path.dart' as path;

final fictionBookFixtureImage = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jrZkAAAAASUVORK5CYII=',
);

String fictionBookXhtml(String content) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>FictionBook export fixture</title></head><body>$content</body></html>''';

EpubDocument fictionBookFixture() {
  final book = EpubDocument.create(
    title: 'An edited shelf — 日本語 & café',
    authors: ['Zoë Writer', '王 小明'],
    language: 'en',
    description: 'First description paragraph.\n\nSecond & final paragraph.',
  );
  book.replaceCover(
    Uint8List.fromList(fictionBookFixtureImage),
    mediaType: 'image/png',
  );
  final first = book.chapters.first;
  final second = book.addChapter(
    title: 'Second chapter',
    xhtml: fictionBookXhtml('''<h1 id="chapter-two">Second chapter</h1>
<p id="café-日本語">A corrected destination — 東京.</p>
<p><a href="chapter-1.xhtml#start">Back to start</a></p>'''),
  );
  final imageHref = path.posix.relative(
    book.coverPath!,
    from: path.posix.dirname(first.path),
  );
  final secondHref = path.posix.basename(second.path);
  book.updateText(
    first.path,
    fictionBookXhtml('''<h1 id="start">Chapter 1</h1>
<p id="formatting">Keep <strong>bold &amp; exact</strong>, <em>italic</em>,
<s>old</s>, H<sub>2</sub>O, x<sup>2</sup> and <code>code()</code>.</p>
<p>A line <em>before<br/>after</em> the break.</p>
<p><a href="$secondHref#caf%C3%A9-%E6%97%A5%E6%9C%AC%E8%AA%9E">Cross-chapter link</a>
and <a href="#note-one" epub:type="noteref">note 1</a>.</p>
<section id="nested"><h2>Nested shelf</h2><p>Inside a nested section.</p>
<p><img src="$imageHref" alt="A tiny cover"/></p></section>
<p>Text after the nested section stays after it.</p>
<blockquote id="quote"><p>A quoted <em>phrase</em>.</p></blockquote>
<ol start="3"><li>Third item</li><li>Fourth item<ul><li>Nested item</li></ul></li></ol>
<table id="table"><caption>Small table</caption><thead><tr><th>A</th><th>B</th></tr></thead>
<tbody><tr><td colspan="2">A <strong>wide</strong> cell</td></tr></tbody></table>
<pre id="code">line one\nline two</pre>
<aside epub:type="footnote" id="note-one"><h3>Note one</h3><p>Footnote body
<a href="#start">return</a>.</p></aside>
<p><a href="https://example.org/book">External reference</a>.</p>'''),
  );
  return book;
}
