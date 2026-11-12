import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '/src/ftp_reply.dart';
import '../ftpconnect.dart';
import '../ftp_transport.dart';

class FTPSocket {
  final String host;
  final int port;
  final Logger logger;
  final int timeout;
  final SecurityType securityType;
  final SecurityContext? securityContext;
  bool _hasSocket = false;
  FtpSocketTransport? _transport;
  FtpSocketTransport? _connectingTransport;
  final _dataTransports = <FtpSocketTransport>{};
  int _pendingResponses = 0;
  RawSocket get _socket =>
      _transport?.raw ??
      (throw FTPConnectException('The FTP connection is closed.'));
  TransferMode transferMode = TransferMode.passive;
  TransferType _transferType = TransferType.auto;
  ListCommand listCommand = ListCommand.mlsd;
  bool supportIPV6 = false;

  FTPSocket(
    this.host,
    this.port,
    this.securityType,
    this.logger,
    this.timeout, {
    this.securityContext,
  });

  /// Register ownership before TCP/TLS awaits so disconnect can always stop
  /// a pending passive connection, including a never-finishing TLS handshake.
  Future<FtpSocketTransport> openDataSocket(int port) async {
    if (!_hasSocket || _transport?.isClosed != false) {
      throw FTPConnectException('The FTP connection is closed.');
    }
    final data = FtpSocketTransport();
    _dataTransports.add(data);
    try {
      await data.connect(
        _socket.remoteAddress,
        port,
        timeout: Duration(seconds: timeout),
      );
      return data;
    } catch (_) {
      closeDataSocket(data);
      rethrow;
    }
  }

  /// Negotiate private data channels with the same hostname/trust policy as
  /// the control connection. No invalid-certificate callback is installed.
  Future<Socket> protectDataSocket(FtpSocketTransport data) async {
    if (!_dataTransports.contains(data)) {
      throw FTPConnectException('The FTP data connection is closed.');
    }
    if (securityType != SecurityType.ftp) {
      await data.secure(
        host,
        timeout: Duration(seconds: timeout),
        securityContext: securityContext,
      );
    }
    return data.socket;
  }

  void closeDataSocket(FtpSocketTransport data) {
    _dataTransports.remove(data);
    data.close();
  }

  void _validateCommand(String command) {
    if (RegExp(r'[\r\n\x00]').hasMatch(command)) {
      throw ArgumentError('FTP commands cannot contain control characters.');
    }
  }

  void _logCommand(String command) {
    final verb = command.split(' ').first.toUpperCase();
    logger.log(
      verb == 'PASS' || verb == 'ACCT' ? '> $verb <redacted>' : '> $command',
    );
  }

  /// Set current transfer type of socket
  ///
  /// Supported types are: [TransferType.auto], [TransferType.ascii], [TransferType.binary],
  TransferType get transferType => _transferType;

  /// Read the FTP Server response from the Stream
  ///
  /// Blocks until data is received!
  Future<FTPReply> readResponse() async {
    _pendingResponses++;
    try {
      return await _readResponse();
    } finally {
      _pendingResponses--;
    }
  }

  Future<FTPReply> _readResponse() async {
    final transport = _transport;
    if (transport == null || transport.isClosed) {
      throw FTPConnectException('The FTP connection is closed.');
    }
    final elapsed = Stopwatch()..start();
    StringBuffer res = StringBuffer();
    while (true) {
      if (!identical(transport, _transport) || transport.isClosed) {
        throw FTPConnectException('The FTP connection is closed.');
      }
      bool dataReceivedSuccessfully = false;

      //this is used to read all data for specific command line
      while (_socket.available() > 0) {
        res.write(Utf8Codec().decode(_socket.read()!).trim());
        dataReceivedSuccessfully = true;
      }
      if (dataReceivedSuccessfully) break;
      if (elapsed.elapsed >= Duration(seconds: timeout)) {
        transport.close();
        throw FTPConnectException('Timeout reached for Receiving response !');
      }
      await Future.any<void>([
        Future<void>.delayed(const Duration(milliseconds: 30)),
        transport.whenClosed,
      ]);
    }

    String r = res.toString();
    if (r.startsWith("\n")) r = r.replaceFirst("\n", "");

    if (r.length < 3) throw FTPConnectException("Illegal Reply Exception", r);

    int? code;
    List<String> lines = r.split('\n');
    //get last code
    String? line;
    for (line in lines) {
      if (line.length >= 3) code = int.tryParse(line.substring(0, 3)) ?? code;
    }
    //multiline response
    if (line != null && line.length >= 4 && line[3] == '-') {
      return await readResponse();
    }

    if (code == null) throw FTPConnectException("Illegal Reply Exception", r);

    FTPReply reply = FTPReply(code, r);
    logger.log('< ${reply.toString()}');
    return reply;
  }

  /// Send a command [cmd] to the FTP Server
  /// if [waitResponse] the function waits for the reply, other wise return ''
  Future<FTPReply> sendCommand(String cmd) {
    _validateCommand(cmd);
    _logCommand(cmd);
    _socket.write(Utf8Codec().encode('$cmd\r\n'));

    return readResponse();
  }

  /// Send a command [cmd] to the FTP Server
  /// if [waitResponse] the function waits for the reply, other wise return ''
  void sendCommandWithoutWaitingResponse(String cmd) {
    _validateCommand(cmd);
    _logCommand(cmd);
    _socket.write(Utf8Codec().encode('$cmd\r\n'));
  }

  /// Connect to the FTP Server and Login with [user] and [pass]
  Future<bool> connect(String user, String pass, {String? account}) async {
    logger.log('Connecting...');

    final timeout = Duration(seconds: this.timeout);
    if (_transport?.isClosed == false) {
      throw FTPConnectException(
          'An FTP connection is already open or pending.');
    }
    final transport = FtpSocketTransport();
    _transport = transport;
    _connectingTransport = transport;
    _hasSocket = false;
    void checkConnection() {
      if (!identical(_transport, transport) || transport.isClosed) {
        throw FTPConnectException('The original FTP connection was closed.');
      }
    }

    Future<FTPReply> send(String command) {
      checkConnection();
      return sendCommand(command);
    }

    try {
      await transport.connect(
        host,
        port,
        timeout: timeout,
        tlsHost: securityType == SecurityType.ftps ? host : null,
        securityContext: securityContext,
      );
      checkConnection();
    } catch (e) {
      transport.close();
      if (identical(_connectingTransport, transport)) {
        _connectingTransport = null;
      }
      throw FTPConnectException(
        'Could not connect to $host ($port)',
        e.toString(),
      );
    }

    _hasSocket = true;
    try {
      logger.log('Connection established, waiting for welcome message...');
      final greeting = await readResponse();
      checkConnection();
      if (greeting.code != 220) {
        throw FTPConnectException('FTP greeting refused', greeting.message);
      }

      // Explicit TLS upgrades after the greeting, before credentials.
      if (securityType == SecurityType.ftpes) {
        final reply = await send('AUTH TLS');
        if (reply.code != 234) {
          throw FTPConnectException(
            'FTP server refused AUTH TLS',
            reply.message,
          );
        }
        await transport.secure(
          host,
          timeout: timeout,
          securityContext: securityContext,
        );
      }

      if (securityType != SecurityType.ftp) {
        for (final command in ['PBSZ 0', 'PROT P']) {
          final reply = await send(command);
          if (reply.code != 200) {
            throw FTPConnectException(
              'FTP TLS data protection refused',
              reply.message,
            );
          }
        }
      }

      // Send Username
      FTPReply lResp = await send('USER $user');

      //password required
      if (lResp.code == 331) {
        lResp = await send('PASS $pass');
        if (lResp.code == 332) {
          if (account == null) throw FTPConnectException('Account required');
          lResp = await send('ACCT $account');
          if (!lResp.isSuccessCode()) {
            throw FTPConnectException('Wrong Account', lResp.message);
          }
        } else if (!lResp.isSuccessCode()) {
          throw FTPConnectException('Wrong Username/password', lResp.message);
        }
        //account required
      } else if (lResp.code == 332) {
        if (account == null) throw FTPConnectException('Account required');
        lResp = await send('ACCT $account');
        if (!lResp.isSuccessCode()) {
          throw FTPConnectException('Wrong Account', lResp.message);
        }
      } else if (!lResp.isSuccessCode()) {
        throw FTPConnectException('Wrong username $user', lResp.message);
      }

      checkConnection();
      logger.log('Connected!');
      return true;
    } catch (_) {
      if (identical(_transport, transport)) _hasSocket = false;
      transport.close();
      rethrow;
    } finally {
      if (identical(_connectingTransport, transport)) {
        _connectingTransport = null;
      }
    }
  }

  Future<FTPReply> openDataTransferChannel() async {
    FTPReply res = FTPReply(200, "");
    if (transferMode == TransferMode.active) {
      //todo later
    } else {
      res = await sendCommand(supportIPV6 ? 'EPSV' : 'PASV');
      if (!res.isSuccessCode()) {
        throw FTPConnectException('Could not start Passive Mode', res.message);
      }
    }

    return res;
  }

  /// Set the Transfer mode on [socket] to [mode]
  Future<void> setTransferType(TransferType pTransferType) async {
    //if we already in the same transfer type we do nothing
    if (_transferType == pTransferType) return;
    switch (pTransferType) {
      case TransferType.auto:
        // Set to ASCII mode
        await sendCommand('TYPE A');
        break;
      case TransferType.ascii:
        // Set to ASCII mode
        await sendCommand('TYPE A');
        break;
      case TransferType.binary:
        // Set to BINARY mode
        await sendCommand('TYPE I');
        break;
    }
    _transferType = pTransferType;
  }

  // Disconnect from the FTP Server
  Future<bool> disconnect() async {
    logger.log('Disconnecting...');
    final transport = _transport;
    if (transport == null) return true;
    final interrupted = _connectingTransport != null ||
        _dataTransports.isNotEmpty ||
        _pendingResponses > 0;
    for (final data in _dataTransports.toList()) {
      closeDataSocket(data);
    }

    try {
      // QUIT cannot be sent in the middle of TLS negotiation or while another
      // command owns the transfer reply. Cancellation closes immediately.
      if (!interrupted && _hasSocket && !transport.isClosed) {
        await sendCommand('QUIT');
      }
    } catch (ignored) {
      // Ignore
    } finally {
      transport.close();
      if (identical(_transport, transport)) {
        _hasSocket = false;
        _transport = null;
      }
    }

    logger.log('Disconnected!');
    return true;
  }
}
