/// EPUB package editing without converting untouched content through an editor
/// document model. This library has no Flutter or platform IO dependency.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:crypto/crypto.dart' as crypto;
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart' as xml_events;

part 'src/models.dart';
part 'src/zip_container.dart';
part 'src/document.dart';
part 'src/prose.dart';
part 'src/fictionbook.dart';
