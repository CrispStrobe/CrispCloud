import 'package:flutter/widgets.dart';

import '../models/file_view_configuration.dart';
import '../models/sort.dart';
import 'commander_strings.dart';

extension LocalizedColumnDefinition on FileColumnDefinition {
  String localizedLabel(BuildContext context) =>
      localizeLabel ? context.commanderTr(label) : label;
}

extension LocalizedFileViewDisplay on FileViewDisplay {
  String localizedLabel(BuildContext context) =>
      context.commanderTr(switch (this) {
        FileViewDisplay.full => 'Full view',
        FileViewDisplay.brief => 'Brief view',
        FileViewDisplay.tree => 'Tree view',
        FileViewDisplay.grid => 'Grid view',
        FileViewDisplay.column => 'Column view',
        FileViewDisplay.tiles => 'Tiles',
        FileViewDisplay.gallery => 'Gallery',
      });
}

extension LocalizedFileColumnKind on FileColumnKind {
  String get englishLabel => switch (this) {
    FileColumnKind.size => 'Size',
    FileColumnKind.modified => 'Date',
    FileColumnKind.extension => 'Extension',
    FileColumnKind.path => 'Path',
    FileColumnKind.source => 'Source',
    FileColumnKind.status => 'Status',
    FileColumnKind.metadata => 'Metadata',
  };

  String localizedLabel(BuildContext context) =>
      context.commanderTr(englishLabel);
}

extension LocalizedSortBy on SortBy {
  String localizedLabel(BuildContext context) =>
      context.commanderTr(switch (this) {
        SortBy.name => 'Name',
        SortBy.size => 'Size',
        SortBy.date => 'Date',
        SortBy.extension => 'Extension',
      });
}

extension LocalizedSortOrder on SortOrder {
  String localizedLabel(BuildContext context) =>
      context.commanderTr(switch (this) {
        SortOrder.ascending => 'Ascending',
        SortOrder.descending => 'Descending',
      });
}
