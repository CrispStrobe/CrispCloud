/// Builds unique Windows Alt-key mnemonics without corrupting literal '&'
/// characters in translated or user-customized top-level menu labels.
///
/// MenuAcceleratorLabel expects '&' before the mnemonic character and '&&'
/// for a literal ampersand. Reuse [used] across one menu bar.
String windowsMenuAcceleratorLabel(String label, Set<String> used) {
  for (var i = 0; i < label.length; i++) {
    final character = label[i].toLowerCase();
    if (RegExp(r'^[a-z]$').hasMatch(character) && used.add(character)) {
      final before = label.substring(0, i).replaceAll('&', '&&');
      final after = label.substring(i).replaceAll('&', '&&');
      return before + '&' + after;
    }
  }
  return label.replaceAll('&', '&&');
}
