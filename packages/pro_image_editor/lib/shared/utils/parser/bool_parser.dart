/// Safely parses a dynamic [value] to a boolean.
///
/// Accepts `true`, `'true'`, `'t'`, 1 as true, and `false`, `'false'`, `'f'`, 0
/// as false. Returns [fallback] if the value is unrecognized.
bool safeParseBool(dynamic value, {bool fallback = false}) {
  if (value == true || value == 'true' || value == 't' || value == 1) {
    return true;
  }

  if (value == false || value == 'false' || value == 'f' || value == 0) {
    return false;
  }

  return fallback;
}
