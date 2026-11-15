import 'dart:convert';

import 'ssh_terminal_config.dart';

enum SshConfigImportSeverity { warning, error }

class SshConfigImportDiagnostic {
  const SshConfigImportDiagnostic({
    required this.code,
    required this.message,
    this.lineNumber = 0,
    this.directive = '',
    this.severity = SshConfigImportSeverity.error,
  });

  final String code;
  final String message;
  final int lineNumber;
  final String directive;
  final SshConfigImportSeverity severity;
}

/// A path displayed for review only. Import never opens or expands this path.
class SshConfigIdentityHint {
  const SshConfigIdentityHint({required this.alias, required this.path});
  final String alias;
  final String path;
}

class SshConfigImportEntry {
  SshConfigImportEntry({
    required this.alias,
    required this.config,
    required List<SshConfigIdentityHint> identityFileHints,
    required List<SshConfigImportDiagnostic> diagnostics,
  }) : identityFileHints = List.unmodifiable(identityFileHints),
       diagnostics = List.unmodifiable(diagnostics);

  final String alias;
  final SshTerminalConfig? config;
  final List<SshConfigIdentityHint> identityFileHints;
  final List<SshConfigImportDiagnostic> diagnostics;
  bool get canImport => config != null;
}

class SshConfigImportResult {
  SshConfigImportResult({
    required List<SshConfigImportEntry> entries,
    required List<SshConfigImportDiagnostic> diagnostics,
  }) : entries = List.unmodifiable(entries),
       diagnostics = List.unmodifiable(diagnostics);

  final List<SshConfigImportEntry> entries;
  final List<SshConfigImportDiagnostic> diagnostics;
}

/// A deliberately bounded, reviewable subset of OpenSSH configuration.
///
/// Only literal positive Host aliases create entries. Host patterns use the
/// original, case-sensitive alias; directive names are case-insensitive. Scalar
/// settings use the first matching value, while IdentityFile is additive.
/// Includes, Match evaluation, commands, key reads and environment access are
/// never performed. Unsupported connection semantics block the affected entry.
/// See https://man.openbsd.org/ssh_config for the source format.
abstract final class SshConfigImport {
  static const maxCharacters = 128 * 1024;
  static const maxLines = 2048;
  static const maxLineCharacters = 4096;
  static const maxAliases = 100;

  static SshConfigImportResult parse(
    String text, {
    String defaultUsername = '',
  }) {
    try {
      return _Parser(text, defaultUsername).parse();
    } on _ImportLimit {
      return SshConfigImportResult(
        entries: const [],
        diagnostics: const [
          SshConfigImportDiagnostic(
            code: 'limit',
            message: 'The SSH configuration exceeds the import limits.',
          ),
        ],
      );
    }
  }
}

class _Option {
  const _Option(this.keyword, this.arguments, this.line);
  final String keyword;
  final List<String> arguments;
  final int line;
}

class _Block {
  _Block(this.patterns);
  final List<String> patterns;
  final List<_Option> options = [];
}

class _Settings {
  final values = <String, _Option>{};
  final identities = <_Option>[];
  final diagnostics = <SshConfigImportDiagnostic>[];
  _Option? proxy;
}

class _ImportLimit implements Exception {}

class _Parser {
  _Parser(this.text, this.defaultUsername);
  final String text;
  final String defaultUsername;
  final blocks = <_Block>[];
  final aliases = <String>{};
  final diagnostics = <SshConfigImportDiagnostic>[];
  final cache = <String, _Settings>{};
  var matchWork = 0;

  static final _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]');
  static final _endpointSpecial = RegExp(r'''[\s"'`$%!*?]''');
  static const _scalar = {'hostname', 'user', 'port'};
  static const _advisory = {
    'serveraliveinterval',
    'serveralivecountmax',
    'tcpkeepalive',
    'connecttimeout',
    'connectionattempts',
    'compression',
    'loglevel',
    'visualhostkey',
    'hashknownhosts',
  };

  SshConfigImportResult parse() {
    if (text.length > SshConfigImport.maxCharacters) throw _ImportLimit();
    final lines = const LineSplitter().convert(text);
    if (lines.length > SshConfigImport.maxLines) throw _ImportLimit();
    var block = _Block(const ['*']);
    blocks.add(block);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.length > SshConfigImport.maxLineCharacters) throw _ImportLimit();
      if (_controls.hasMatch(line)) {
        _syntax(i + 1);
        continue;
      }
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final directive = RegExp(
        r'^([A-Za-z][A-Za-z0-9]*)(?:[ \t]*=[ \t]*|[ \t]+)(.*)$',
      ).firstMatch(trimmed);
      if (directive == null) {
        _syntax(i + 1);
        continue;
      }
      final keyword = directive.group(1)!.toLowerCase();
      final arguments = _tokens(directive.group(2)!);
      if (arguments == null || arguments.isEmpty) {
        _syntax(i + 1, keyword);
        continue;
      }
      if ({..._scalar, 'proxyjump', 'identityfile'}.contains(keyword) &&
          (arguments.length != 1 || arguments.single.isEmpty)) {
        _syntax(i + 1, keyword);
        continue;
      }
      if (keyword == 'host') {
        if (arguments.length > 64 ||
            arguments.any((p) => p.length > 253 || p == '!')) {
          _syntax(i + 1, keyword);
          continue;
        }
        block = _Block(arguments);
        blocks.add(block);
        for (final pattern in arguments) {
          if (!pattern.startsWith('!') &&
              !pattern.contains('*') &&
              !pattern.contains('?')) {
            aliases.add(pattern);
            if (aliases.length > SshConfigImport.maxAliases) {
              throw _ImportLimit();
            }
          }
        }
      } else if (keyword == 'match' || keyword == 'include') {
        // Both can alter parsing of the following configuration, even when
        // encountered inside a Host block. Do not guess their effective scope.
        diagnostics.add(
          SshConfigImportDiagnostic(
            code: 'external-semantics',
            message: 'Flatten Match and Include sections before importing.',
            directive: keyword,
            lineNumber: i + 1,
          ),
        );
        if (keyword == 'match') {
          block = _Block(const []);
          blocks.add(block);
        }
      } else {
        block.options.add(_Option(keyword, arguments, i + 1));
      }
      if (diagnostics.length > 64) throw _ImportLimit();
    }
    final entries = aliases.map(_entry).toList();
    if (entries.isEmpty && diagnostics.isEmpty) {
      diagnostics.add(
        const SshConfigImportDiagnostic(
          code: 'no-aliases',
          message: 'No literal Host aliases were found.',
          severity: SshConfigImportSeverity.warning,
        ),
      );
    }
    return SshConfigImportResult(entries: entries, diagnostics: diagnostics);
  }

  void _syntax(int line, [String directive = '']) {
    diagnostics.add(
      SshConfigImportDiagnostic(
        code: 'syntax',
        message: 'Invalid or unsupported SSH configuration syntax.',
        lineNumber: line,
        directive: directive,
      ),
    );
    if (diagnostics.length > 64) throw _ImportLimit();
  }

  List<String>? _tokens(String text) {
    final tokens = <String>[];
    var token = StringBuffer();
    var quoted = false;
    var started = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\\') {
        if (i + 1 == text.length) return null;
        final next = text[i + 1];
        // Do not silently reinterpret shell escapes or line continuation.
        if (next != '"' && next != '\\' && next != ' ' && next != '\t') {
          return null;
        }
        token.write(next);
        i++;
        started = true;
      } else if (char == '"') {
        quoted = !quoted;
        started = true;
      } else if (!quoted && char == '#') {
        break;
      } else if (!quoted && (char == ' ' || char == '\t')) {
        if (started) {
          tokens.add(token.toString());
          token = StringBuffer();
          started = false;
        }
      } else {
        token.write(char);
        started = true;
      }
    }
    if (quoted) return null;
    if (started) tokens.add(token.toString());
    return tokens;
  }

  bool _matches(List<String> patterns, String alias) {
    var positive = false;
    for (final pattern in patterns) {
      final negated = pattern.startsWith('!');
      if (_glob(negated ? pattern.substring(1) : pattern, alias)) {
        if (negated) return false;
        positive = true;
      }
    }
    return positive;
  }

  bool _glob(String pattern, String value) {
    var p = 0;
    var v = 0;
    var star = -1;
    var retry = 0;
    while (v < value.length) {
      if (++matchWork > 1000000) throw _ImportLimit();
      if (p < pattern.length && (pattern[p] == '?' || pattern[p] == value[v])) {
        p++;
        v++;
      } else if (p < pattern.length && pattern[p] == '*') {
        star = p++;
        retry = v;
      } else if (star >= 0) {
        p = star + 1;
        v = ++retry;
      } else {
        return false;
      }
    }
    while (p < pattern.length && pattern[p] == '*') {
      p++;
    }
    return p == pattern.length;
  }

  _Settings _settings(String alias) => cache.putIfAbsent(alias, () {
    final settings = _Settings();
    final seen = <String>{};
    for (final block in blocks) {
      if (!_matches(block.patterns, alias)) continue;
      for (final option in block.options) {
        final keyword = option.keyword;
        if (keyword == 'proxyjump' || keyword == 'proxycommand') {
          final previous = settings.proxy;
          // OpenSSH's disabled ProxyJump still wins over another ProxyJump,
          // but leaves ProxyCommand available. ProxyCommand none, in contrast,
          // suppresses both later directives. Treat none case-insensitively.
          final disabledJump =
              previous?.keyword == 'proxyjump' &&
              previous!.arguments.length == 1 &&
              previous.arguments.single.toLowerCase() == 'none';
          if (previous != null &&
              !(keyword == 'proxycommand' && disabledJump)) {
            continue;
          }
          settings.proxy = option;
        } else if (keyword == 'identityfile') {
          if (option.arguments.length != 1 ||
              option.arguments.single.isEmpty ||
              option.arguments.single.length > 1024) {
            settings.diagnostics.add(_invalid(option));
          } else if (option.arguments.single != 'none') {
            settings.identities.add(option);
            if (settings.identities.length > 16) throw _ImportLimit();
          }
        } else if (seen.add(keyword)) {
          if (_scalar.contains(keyword)) {
            settings.values[keyword] = option;
          } else {
            settings.diagnostics.add(
              SshConfigImportDiagnostic(
                code: _advisory.contains(keyword) ? 'advisory' : 'unsupported',
                message: _advisory.contains(keyword)
                    ? 'This option is not carried into the saved profile.'
                    : 'This option is unsupported; this alias cannot be imported.',
                directive: keyword,
                lineNumber: option.line,
                severity: _advisory.contains(keyword)
                    ? SshConfigImportSeverity.warning
                    : SshConfigImportSeverity.error,
              ),
            );
          }
        }
        if (settings.diagnostics.length > 64) throw _ImportLimit();
      }
    }
    return settings;
  });

  SshConfigImportDiagnostic _invalid(_Option option) =>
      SshConfigImportDiagnostic(
        code: 'value',
        message: 'Invalid or unsupported value for this SSH option.',
        directive: option.keyword,
        lineNumber: option.line,
      );

  String? _one(_Option? option, List<SshConfigImportDiagnostic> errors) {
    if (option == null) return null;
    if (option.arguments.length != 1 || option.arguments.single.isEmpty) {
      errors.add(_invalid(option));
      return null;
    }
    return option.arguments.single;
  }

  ({String host, int port, String username}) _destination(
    String alias,
    _Settings settings,
    List<SshConfigImportDiagnostic> errors, {
    String? explicitUser,
    int? explicitPort,
  }) {
    var host = _one(settings.values['hostname'], errors) ?? alias;
    if (host.contains('%')) {
      final expanded = StringBuffer();
      for (var i = 0; i < host.length; i++) {
        if (host[i] != '%') {
          expanded.write(host[i]);
          continue;
        }
        if (++i == host.length || (host[i] != 'h' && host[i] != '%')) {
          errors.add(_invalid(settings.values['hostname']!));
          break;
        }
        expanded.write(host[i] == 'h' ? alias : '%');
      }
      host = expanded.toString();
    }
    final username =
        explicitUser ??
        _one(settings.values['user'], errors) ??
        defaultUsername;
    final rawPort = _one(settings.values['port'], errors);
    final port = explicitPort ?? (rawPort == null ? 22 : int.tryParse(rawPort));
    if (username.isEmpty) {
      errors.add(
        const SshConfigImportDiagnostic(
          code: 'missing-user',
          message: 'Set User or provide a default username before importing.',
        ),
      );
    }
    if (!SshJumpHost.isValidHost(host) ||
        _endpointSpecial.hasMatch(host) ||
        !SshJumpHost.isValidUsername(username) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        (rawPort != null && !RegExp(r'^[0-9]+$').hasMatch(rawPort))) {
      errors.add(
        const SshConfigImportDiagnostic(
          code: 'destination',
          message: 'The resolved SSH destination is invalid.',
        ),
      );
    }
    return (host: host, port: port ?? 22, username: username);
  }

  ({String alias, String? user, int? port})? _jump(String value) {
    if (value.isEmpty || value.contains('%') || value.contains(r'$')) {
      return null;
    }
    if (value.startsWith('ssh://')) {
      // Parse the endpoint explicitly: URI normalization can discard a written
      // port zero. A configuration import must reject it, never substitute 22.
      value = value.substring(6);
      if (value.contains('/') || value.contains('?') || value.contains('#')) {
        return null;
      }
    }
    String? user;
    var host = value;
    final at = value.indexOf('@');
    if (at >= 0) {
      if (at == 0 || value.indexOf('@', at + 1) >= 0) return null;
      user = value.substring(0, at);
      if (user.contains(':')) return null;
      host = value.substring(at + 1);
    }
    String? portText;
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      if (end < 0) return null;
      final suffix = host.substring(end + 1);
      if (suffix.isNotEmpty) {
        if (!suffix.startsWith(':')) return null;
        portText = suffix.substring(1);
      }
      host = host.substring(1, end);
    } else if (host.contains(':')) {
      if (host.indexOf(':') != host.lastIndexOf(':')) return null;
      portText = host.substring(host.indexOf(':') + 1);
      host = host.substring(0, host.indexOf(':'));
    }
    if (host.isEmpty ||
        (portText != null &&
            (!RegExp(r'^[0-9]+$').hasMatch(portText) ||
                int.tryParse(portText) == null))) {
      return null;
    }
    return (
      alias: host,
      user: user,
      port: portText == null ? null : int.parse(portText),
    );
  }

  SshConfigImportEntry _entry(String alias) {
    final settings = _settings(alias);
    final errors = settings.diagnostics.toList();
    final hints = <SshConfigIdentityHint>[];
    void addHints(String name, _Settings selected) {
      for (final identity in selected.identities) {
        hints.add(
          SshConfigIdentityHint(alias: name, path: identity.arguments.single),
        );
      }
    }

    addHints(alias, settings);
    final destination = _destination(alias, settings, errors);
    final jumpHosts = <SshJumpHost>[];
    final proxy = settings.proxy;
    final route = _one(proxy, errors);
    if (route != null && route.toLowerCase() != 'none') {
      if (proxy!.keyword == 'proxycommand') {
        errors.add(
          SshConfigImportDiagnostic(
            code: 'proxycommand',
            message: 'ProxyCommand cannot be imported as a direct connection.',
            directive: proxy.keyword,
            lineNumber: proxy.line,
          ),
        );
      } else {
        final parts = route.split(',');
        if (parts.length > SshJumpHost.maxJumpHosts) {
          errors.add(_invalid(proxy));
        } else {
          for (final part in parts) {
            final jump = _jump(part);
            if (jump == null) {
              errors.add(_invalid(proxy));
              continue;
            }
            final options = _settings(jump.alias);
            errors.addAll(options.diagnostics);
            final nested = _one(options.proxy, errors);
            if (nested != null && nested.toLowerCase() != 'none') {
              errors.add(
                SshConfigImportDiagnostic(
                  code: 'nested-proxy',
                  message: 'Flatten nested jump routes before importing.',
                  directive: options.proxy!.keyword,
                  lineNumber: options.proxy!.line,
                ),
              );
            }
            final target = _destination(
              jump.alias,
              options,
              errors,
              explicitUser: jump.user,
              explicitPort: jump.port,
            );
            addHints(jump.alias, options);
            jumpHosts.add(
              SshJumpHost(
                host: target.host,
                port: target.port,
                username: target.username,
                authentication: options.identities.isEmpty
                    ? SshTerminalAuthentication.password
                    : SshTerminalAuthentication.privateKey,
              ),
            );
          }
        }
      }
    }
    try {
      SshJumpHost.validateRoute(
        host: destination.host,
        port: destination.port,
        username: destination.username,
        jumpHosts: jumpHosts,
      );
    } on ArgumentError {
      errors.add(
        const SshConfigImportDiagnostic(
          code: 'route',
          message: 'The jump route is invalid or contains a repeated endpoint.',
        ),
      );
    }
    final blocked =
        diagnostics.any((d) => d.severity == SshConfigImportSeverity.error) ||
        errors.any((d) => d.severity == SshConfigImportSeverity.error);
    return SshConfigImportEntry(
      alias: alias,
      config: blocked
          ? null
          : SshTerminalConfig(
              host: destination.host,
              port: destination.port,
              username: destination.username,
              jumpHosts: List.unmodifiable(jumpHosts),
              authentication: settings.identities.isEmpty
                  ? SshTerminalAuthentication.password
                  : SshTerminalAuthentication.privateKey,
            ),
      identityFileHints: hints,
      diagnostics: errors,
    );
  }
}
