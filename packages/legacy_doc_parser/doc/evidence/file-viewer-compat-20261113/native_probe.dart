import 'dart:convert';
import 'dart:io';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

void main(List<String> args) {
  final watch = Stopwatch()..start();
  try {
    final parsed = parseLegacyWordDocument(File(args.single).readAsBytesSync());
    var paragraphs = 0, tables = 0, rows = 0, cells = 0;
    var insertedRuns = 0, deletedRuns = 0, historicalRuns = 0;
    void walk(List<LegacyWordBlock> blocks) {
      for (final block in blocks) {
        if (block is LegacyWordParagraph) {
          paragraphs++;
          for (final run in block.runs) {
            if (run.inserted) insertedRuns++;
            if (run.deleted) deletedRuns++;
            if (run.formattingRevision != null) historicalRuns++;
          }
        }
        if (block is! LegacyWordTable) continue;
        tables++;
        for (final row in block.rows) {
          rows++;
          for (final cell in row.cells) {
            cells++;
            walk(cell.blocks);
          }
        }
      }
    }
    walk(parsed.blocks);
    final bodyCounts = {'paragraphs':paragraphs,'tables':tables,'rows':rows,'cells':cells};
    for (final story in parsed.stories) { walk(story.blocks); }
    stdout.writeln(jsonEncode({
      'ok':true,'elapsedMs':watch.elapsedMicroseconds/1000,
      'bodyCounts':bodyCounts,'allCounts':{'paragraphs':paragraphs,'tables':tables,'rows':rows,'cells':cells},
      'warnings':parsed.warnings.map((e)=>e.name).toList(),
      'sections':parsed.sections.length,'numberingDefinitions':parsed.numbering.length,
      'tableStyles':parsed.tableStyles.length,'bookmarks':parsed.bookmarks.length,'fields':parsed.fields.length,
      'noteReferences':parsed.noteReferences.length,'commentReferences':parsed.commentReferences.length,
      'textboxReferences':parsed.textboxReferences.length,
      'unpositionedTextboxes':parsed.textboxReferences.where((r)=>r.placementUnresolved).length,
      'media':{'assets':parsed.media.assets.length,'pictures':parsed.media.pictures.length,
        'drawings':parsed.media.drawings.length,'objects':parsed.media.embeddedObjects.length,
        'vbaProjects':parsed.media.vbaProjects.length,
        'notices':parsed.media.notices.map((e)=>e.issue.name).toList()},
      'revisions':{'insertedRuns':insertedRuns,'deletedRuns':deletedRuns,'historicalRuns':historicalRuns},
      'plainText':parsed.plainText,'html':parsed.safeHtml,
      'stories':parsed.stories.map((s)=>{'id':s.id,'kind':s.kind.name,'plainText':s.plainText,'html':s.safeHtml}).toList(),
    }));
  } catch(error) {
    stdout.writeln(jsonEncode({'ok':false,'elapsedMs':watch.elapsedMicroseconds/1000,'error':error.toString()}));
  }
}
