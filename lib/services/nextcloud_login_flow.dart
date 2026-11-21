// Nextcloud Login Flow v2: the user signs in on the server's own web page
// (any SSO, two-factor or email-alias login the server supports) and approves
// CrispCloud there. The server then hands out a dedicated app password.
//
// https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html#login-flow-v2

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class NextcloudLoginFlowException implements Exception {
  const NextcloudLoginFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Credentials granted by the server after the user approved the login.
class NextcloudLoginFlowResult {
  const NextcloudLoginFlowResult({
    required this.server,
    required this.loginName,
    required this.appPassword,
  });

  final Uri server;
  final String loginName;
  final String appPassword;
}

class NextcloudLoginFlow {
  NextcloudLoginFlow._(
    this.server,
    this.loginUrl,
    this._pollUrl,
    this._token,
    this._client,
  );

  /// Installation root the flow was started on.
  final Uri server;

  /// Page the user must open in a browser to sign in and approve access.
  final Uri loginUrl;

  final Uri _pollUrl;
  final String _token;
  final http.Client _client;

  /// Name Nextcloud shows for the generated app password.
  static const userAgent = 'CrispCloud';

  /// Starts a flow on the installation root [server] (no `remote.php` part).
  static Future<NextcloudLoginFlow> start(
    Uri server, {
    http.Client? client,
  }) async {
    final http.Client effective = client ?? http.Client();
    final base = server.toString().replaceFirst(RegExp(r'/+$'), '');
    final http.Response response;
    try {
      response = await effective
          .post(
            Uri.parse('$base/index.php/login/v2'),
            headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      if (client == null) effective.close();
      throw NextcloudLoginFlowException('Browser login could not start: $e');
    }
    try {
      if (response.statusCode != 200) {
        throw NextcloudLoginFlowException(
          'Browser login is not available on this server '
          '(HTTP ${response.statusCode}).',
        );
      }
      final body = json.decode(response.body);
      final poll = body is Map ? body['poll'] : null;
      final login = body is Map ? Uri.tryParse('${body['login']}') : null;
      final token = poll is Map ? poll['token'] : null;
      final endpoint = poll is Map ? Uri.tryParse('${poll['endpoint']}') : null;
      if (login == null ||
          token is! String ||
          token.isEmpty ||
          endpoint == null ||
          !_isWeb(login) ||
          !_isWeb(endpoint) ||
          // The poll token is a bearer secret for the app password: it may
          // only ever go back to the installation the user chose.
          endpoint.origin != server.origin) {
        throw const NextcloudLoginFlowException(
          'The server returned an invalid browser login response.',
        );
      }
      return NextcloudLoginFlow._(server, login, endpoint, token, effective);
    } catch (_) {
      if (client == null) effective.close();
      rethrow;
    }
  }

  static bool _isWeb(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;

  /// One poll. Returns null while the user has not yet approved.
  Future<NextcloudLoginFlowResult?> poll() async {
    final response = await _client
        .post(
          _pollUrl,
          headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          body: {'token': _token},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw NextcloudLoginFlowException(
        'Browser login failed (HTTP ${response.statusCode}).',
      );
    }
    final body = json.decode(response.body);
    final loginName = body is Map ? body['loginName'] : null;
    final appPassword = body is Map ? body['appPassword'] : null;
    if (loginName is! String ||
        loginName.isEmpty ||
        appPassword is! String ||
        appPassword.isEmpty) {
      throw const NextcloudLoginFlowException(
        'The server returned an invalid browser login result.',
      );
    }
    // Prefer the server's own canonical address (it knows its subfolder),
    // but never let the response move the credentials to another origin.
    final reported = body is Map ? Uri.tryParse('${body['server']}') : null;
    final resolved =
        reported != null &&
            _isWeb(reported) &&
            reported.origin == server.origin &&
            !reported.hasQuery &&
            !reported.hasFragment
        ? Uri.parse(reported.toString().replaceFirst(RegExp(r'/+$'), ''))
        : server;
    return NextcloudLoginFlowResult(
      server: resolved,
      loginName: loginName,
      appPassword: appPassword,
    );
  }

  /// Polls until approval, [cancelled] returns true, or [timeout] passes.
  /// Nextcloud expires an unused flow after 20 minutes.
  Future<NextcloudLoginFlowResult?> waitForApproval({
    bool Function()? cancelled,
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (cancelled?.call() ?? false) return null;
        final result = await poll();
        if (result != null) return result;
        await Future<void>.delayed(interval);
      }
      return null;
    } finally {
      close();
    }
  }

  void close() => _client.close();
}
