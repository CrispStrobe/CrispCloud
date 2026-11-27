import 'productivity_action.dart';
import 'productivity_snapshot.dart' show ProductivityKind;

/// An immutable suggestion that must be reviewed by the host user.
final class ProductivityProposal {
  const ProductivityProposal._(
    this.title,
    this.text,
    this.start,
    this.end, {
    this.action,
  });

  final String title;
  final String text;
  final DateTime? start;
  final DateTime? end;
  final ProductivityActionPlan? action;
}

enum ProductivityApprovalOutcome { saved, queued, sent, rejected, unconfirmed }

final class ProductivityProposals {
  ProductivityProposals(this.kind);

  final ProductivityKind kind;
  ProductivityProposal? _pending;
  int _serial = 0;
  String _status = 'none';

  bool get _applying => _status == 'applying';
  ProductivityProposal? get pending => _applying ? null : _pending;
  String get tool => switch (kind) {
    ProductivityKind.mail => 'mail_propose_draft',
    ProductivityKind.tasks => 'tasks_propose_create',
    ProductivityKind.calendar => 'calendar_propose_appointment',
  };

  Map<String, Object?> get status => {
    'status': _status,
    if (_serial > 0) 'proposal': _serial,
  };

  Map<String, Object?> propose(Map<String, Object?> arguments) {
    if (_pending != null) {
      throw StateError('A proposal is already awaiting review');
    }
    final calendar = kind == ProductivityKind.calendar;
    if (arguments.keys.any(
      (key) =>
          key != 'title' &&
          key != 'text' &&
          (!calendar || (key != 'start' && key != 'end')),
    )) {
      throw const FormatException('Unexpected proposal field');
    }
    final title = arguments['title'];
    final text = arguments.containsKey('text') ? arguments['text'] : '';
    if (title is! String ||
        title.trim().isEmpty ||
        title.length > 250 ||
        title.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        text is! String ||
        text.length > 3000 ||
        text.contains('\u0000')) {
      throw const FormatException('Invalid proposal title or text');
    }
    final start = calendar ? parseProductivityUtc(arguments['start']) : null;
    final end = calendar ? parseProductivityUtc(arguments['end']) : null;
    if (start != null && (end!.isBefore(start) || end == start)) {
      throw const FormatException('Appointment end must follow start');
    }
    return _queue(ProductivityProposal._(title, text, start, end));
  }

  Map<String, Object?> proposeAction(ProductivityActionPlan plan) => _queue(
    ProductivityProposal._(
      plan.subject,
      plan.details,
      null,
      null,
      action: plan,
    ),
  );

  Map<String, Object?> _queue(ProductivityProposal proposal) {
    if (_pending != null) {
      throw StateError('A proposal is already awaiting review');
    }
    _pending = proposal;
    _serial++;
    _status = 'awaiting_review';
    return status;
  }

  bool resolve(ProductivityProposal proposal, {required bool review}) {
    if (_applying ||
        !identical(_pending, proposal) ||
        (review && proposal.action != null)) {
      return false;
    }
    _pending = null;
    _status = review ? 'reviewed' : 'dismissed';
    return true;
  }

  /// Called by the host only after review. A failed or ambiguous operation
  /// consumes this approval so it cannot be replayed by another click.
  Future<bool> apply(
    ProductivityProposal proposal,
    Future<ProductivityApprovalOutcome> Function() execute,
  ) async {
    if (_applying || !identical(_pending, proposal)) return false;
    _status = 'applying';
    try {
      _status = (await execute()).name;
    } on Object {
      _status = ProductivityApprovalOutcome.unconfirmed.name;
    } finally {
      _pending = null;
    }
    return true;
  }
}

DateTime parseProductivityUtc(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$').hasMatch(value)) {
    throw const FormatException('Use UTC date-time with seconds');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.year < 1900 ||
      parsed.year > 2200 ||
      parsed.toIso8601String() != value.replaceFirst('Z', '.000Z')) {
    throw const FormatException('Invalid appointment time');
  }
  return parsed;
}
