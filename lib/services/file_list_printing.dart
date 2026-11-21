import '../models/file_item.dart';
import '../utils/formatters.dart';

/// Column headers for a printed directory listing, already localised.
typedef FileListPrintLabels = ({String name, String size, String modified});

const _nameWidth = 50, _sizeWidth = 10;

String _two(int value) => value.toString().padLeft(2, '0');

String _timestamp(DateTime? date) {
  if (date == null) return '';
  final d = date.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)} '
      '${_two(d.hour)}:${_two(d.minute)}';
}

/// Plain monospace listing (path header, then name / size / modified columns)
/// that fits an A4 page at the text-print font size. Names longer than the
/// name column get a line of their own so nothing is truncated.
String fileListPrintText(
  String path,
  List<FileItem> files,
  FileListPrintLabels labels,
) {
  final out = StringBuffer()
    ..writeln(path)
    ..writeln()
    ..writeln(
      '${labels.name.padRight(_nameWidth)}  '
      '${labels.size.padLeft(_sizeWidth)}  ${labels.modified}',
    )
    ..writeln('-' * (_nameWidth + _sizeWidth + 20));
  for (final file in files) {
    final name = file.isFolder ? '${file.name}/' : file.name;
    final size = file.isFolder
        ? '<DIR>'
        : file.size == null
        ? ''
        : formatBytes(file.size!);
    final details =
        '${size.padLeft(_sizeWidth)}  ${_timestamp(file.updatedAt)}';
    if (name.length > _nameWidth) {
      out
        ..writeln(name)
        ..writeln('${''.padRight(_nameWidth)}  $details');
    } else {
      out.writeln('${name.padRight(_nameWidth)}  $details');
    }
  }
  return out.toString();
}
