/// Holds localized labels for FloatSelect actions
class FloatSelectI18n {
  /// Creates a set of localized labels
  const FloatSelectI18n({
    this.edit = 'Edit',
    this.forward = 'Forward',
    this.backward = 'Backward',
    this.moveToFront = 'Move To Front',
    this.moveToBack = 'Move To Back',
    this.duplicate = 'Duplicate',
    this.delete = 'Delete',
  });

  /// Label for the edit action
  final String edit;

  /// Label for the forward action
  final String forward;

  /// Label for the backward action
  final String backward;

  /// Label for the move-to-front action
  final String moveToFront;

  /// Label for the move-to-back action
  final String moveToBack;

  /// Label for the duplicate action
  final String duplicate;

  /// Label for the delete action
  final String delete;

  /// Returns a copy with overridden values
  FloatSelectI18n copyWith({
    String? edit,
    String? forward,
    String? backward,
    String? moveToFront,
    String? moveToBack,
    String? duplicate,
    String? delete,
  }) {
    return FloatSelectI18n(
      edit: edit ?? this.edit,
      forward: forward ?? this.forward,
      backward: backward ?? this.backward,
      moveToFront: moveToFront ?? this.moveToFront,
      moveToBack: moveToBack ?? this.moveToBack,
      duplicate: duplicate ?? this.duplicate,
      delete: delete ?? this.delete,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FloatSelectI18n &&
        other.edit == edit &&
        other.forward == forward &&
        other.backward == backward &&
        other.moveToFront == moveToFront &&
        other.moveToBack == moveToBack &&
        other.duplicate == duplicate &&
        other.delete == delete;
  }

  @override
  int get hashCode {
    return edit.hashCode ^
        forward.hashCode ^
        backward.hashCode ^
        moveToFront.hashCode ^
        moveToBack.hashCode ^
        duplicate.hashCode ^
        delete.hashCode;
  }
}
