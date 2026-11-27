import 'productivity_proposal.dart';

/// A grant-local action for a host-selected target. Only the host owns the
/// execution callback and may invoke it after displaying the immutable plan.
final class ProductivityAction {
  ProductivityAction({
    required String label,
    required String destination,
    required String subject,
    required Map<String, int> fields,
    required ProductivityActionPlan Function(Map<String, String>) prepare,
  }) : this._(label, destination, subject, Map.unmodifiable(fields), prepare);

  ProductivityAction._(
    this.label,
    this.destination,
    this.subject,
    this.fields,
    this._prepare,
  );

  final String label;
  final String destination;
  final String subject;
  final Map<String, int> fields;
  final ProductivityActionPlan Function(Map<String, String>) _prepare;

  ProductivityActionPlan plan(Map<String, Object?> args) {
    if (args.length != fields.length ||
        fields.entries.any((field) {
          final value = args[field.key];
          return value is! String ||
              value.length > field.value ||
              value.contains('\u0000');
        })) {
      throw const FormatException('Invalid action fields');
    }
    return _prepare(Map.unmodifiable(args.cast<String, String>()));
  }
}

final class ProductivityActionPlan {
  const ProductivityActionPlan({
    required this.label,
    required this.destination,
    required this.subject,
    required this.details,
    required this.execute,
  });

  final String label;
  final String destination;
  final String subject;
  final String details;
  final Future<ProductivityApprovalOutcome> Function(bool Function()) execute;
}

final class ProductivityActions {
  ProductivityActions(Iterable<ProductivityAction> actions)
    : _actions = List.unmodifiable(actions.take(150));

  final List<ProductivityAction> _actions;

  bool get isEmpty => _actions.isEmpty;

  Map<String, Object?> list({required int offset, required int limit}) => {
    'actions': [
      for (var i = offset; i < offset + limit && i < _actions.length; i++)
        {
          'handle': i + 1,
          'action': _actions[i].label,
          'destination': _title(_actions[i].destination),
          'subject': _title(_actions[i].subject),
          'requiredFields': _actions[i].fields,
        },
    ],
    if (offset + limit < _actions.length) 'nextOffset': offset + limit,
  };

  ProductivityActionPlan plan(int handle, Map<String, Object?> args) {
    if (handle < 1 || handle > _actions.length) {
      throw const FormatException('Unknown action handle');
    }
    return _actions[handle - 1].plan(args);
  }

  static String _title(String value) =>
      String.fromCharCodes(value.runes.take(256));
}
