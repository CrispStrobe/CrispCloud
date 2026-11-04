/// Page chrome: page numbers, header/footer helpers, signature lines.
library;

import 'pw_box.dart';
import 'pw_core.dart';
import 'pw_layout.dart';
import 'pw_style.dart';
import 'pw_text.dart';
import 'pw_types.dart';

/// Builds a page-number widget from the current page and total count.
typedef PageNumberBuilder = Widget Function(int page, int pagesCount);

/// Renders the current page number using [Context.pageNumber] / [pagesCount].
class PageNumber extends Widget {
  /// PageNumber API.
  const PageNumber({
    this.builder,
    this.style,
    this.template = '{page} / {count}',
  });

  /// Custom builder. When set, [template] is ignored.
  final PageNumberBuilder? builder;

  /// Style for the default [template] text.
  final TextStyle? style;

  /// Placeholders: `{page}`, `{count}`.
  final String template;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PageNumberBuilder? custom = builder;
    final Widget child = custom != null
        ? custom(context.pageNumber, context.pagesCount)
        : Text(
            template
                .replaceAll('{page}', '${context.pageNumber}')
                .replaceAll('{count}', '${context.pagesCount}'),
            style:
                style ??
                const TextStyle(fontSize: 9, color: '607D8B'),
          );
    return child.layout(context, constraints);
  }
}

/// Convenience chrome for [MultiPage] headers and footers.
class HeaderFooter extends Widget {
  /// HeaderFooter API.
  const HeaderFooter({
    this.leading,
    this.title,
    this.trailing,
    this.showPageNumber = true,
    this.pageNumber,
    this.padding = const EdgeInsets.only(top: 6, bottom: 4),
    this.divider = false,
    this.dividerColor = 'CFD8DC',
  });

  /// leading API.
  final Widget? leading;

  /// title API.
  final Widget? title;

  /// trailing API.
  final Widget? trailing;

  /// When true and [pageNumber] is null, appends a default [PageNumber].
  final bool showPageNumber;

  /// Optional custom page-number widget (overrides [showPageNumber]).
  final Widget? pageNumber;

  /// padding API.
  final EdgeInsetsGeometry padding;

  /// When true, draws a hairline under the row.
  final bool divider;

  /// dividerColor API.
  final String dividerColor;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final Widget? number = pageNumber ??
        (showPageNumber
            ? const PageNumber(
                style: TextStyle(fontSize: 8, color: '78909C'),
              )
            : null);
    Widget row = Row(
      children: <Widget>[
        leading ?? const SizedBox.shrink(),
        const Spacer(),
        title ?? const SizedBox.shrink(),
        const Spacer(),
        trailing ?? number ?? const SizedBox.shrink(),
      ],
    );
    if (divider) {
      row = Column(
        children: <Widget>[
          row,
          Divider(height: 8, thickness: 0.6, color: dividerColor),
        ],
      );
    }
    return Padding(padding: padding, child: row).layout(context, constraints);
  }
}

/// Signature block: optional label, underline, optional date line.
class SignatureLine extends Widget {
  /// SignatureLine API.
  const SignatureLine({
    this.label = 'Signature',
    this.hint = '',
    this.width = 180,
    this.showDateLine = false,
    this.dateLabel = 'Date',
    this.lineColor = '90A4AE',
    this.labelStyle,
    this.hintStyle,
  });

  /// label API.
  final String label;

  /// hint API (shown above the line, muted).
  final String hint;

  /// width API.
  final double width;

  /// showDateLine API.
  final bool showDateLine;

  /// dateLabel API.
  final String dateLabel;

  /// lineColor API.
  final String lineColor;

  /// labelStyle API.
  final TextStyle? labelStyle;

  /// hintStyle API.
  final TextStyle? hintStyle;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final List<Widget> kids = <Widget>[
      if (hint.isNotEmpty)
        Text(
          hint,
          style:
              hintStyle ??
              const TextStyle(fontSize: 8, color: '90A4AE'),
        ),
      if (hint.isNotEmpty) const SizedBox(height: 18),
      if (hint.isEmpty) const SizedBox(height: 28),
      SizedBox(
        width: width,
        child: Divider(height: 1, thickness: 0.9, color: lineColor),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style:
            labelStyle ??
            const TextStyle(fontSize: 9, color: '455A64'),
      ),
    ];
    if (showDateLine) {
      kids.addAll(<Widget>[
        const SizedBox(height: 16),
        SizedBox(
          width: width * 0.55,
          child: Divider(height: 1, thickness: 0.9, color: lineColor),
        ),
        const SizedBox(height: 4),
        Text(
          dateLabel,
          style:
              labelStyle ??
              const TextStyle(fontSize: 9, color: '455A64'),
        ),
      ]);
    }
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kids,
      ),
    ).layout(context, constraints);
  }
}

/// Keep-together alias for [Inseparable] (MultiPage avoids splitting one box).
class KeepTogether extends Inseparable {
  /// KeepTogether API.
  const KeepTogether({required super.child, super.canSpan = false});
}
