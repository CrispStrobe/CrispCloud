import 'dart:convert';
import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart';
class Probe extends Visitor {
 @override void visitLiteralTerm(LiteralTerm node) { print(jsonEncode({'value':node.value.toString(),'text':node.text})); }
}
void main() {
 for (final text in ["p{font-family:'Arial'}",r"p{font-family:'\41 \72 \69 \61 \6c '}"]) {
  print(text);
  css.parse(text).visit(Probe());
 }
}
