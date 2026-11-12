import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '/src/ftp_reply.dart';
import '../ftpconnect.dart';

class FTPSocket {
  final String host;
  final int port;
  final Logger logger;
  final int timeout;
  final SecurityType securityType;
  final SecurityContext? securityContext;
  bool _hasSocket = false;
  late RawSocket _socket;
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

  /// Negotiate private data channels with the same hostname/trust policy as
  /// the control connection. No invalid-certificate callback is installed.
  Future<Socket> protectDataSocket(Socket socket) async {
    if (securityType == SecurityType.ftp) return socket;
    try {
      return await SecureSocket.secure(
        socket,
        host: host,
        context: securityContext,
      ).timeout(Duration(seconds: timeout));
    } catch (_) {
      socket.destroy();
      rethrow;
    }
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
    StringBuffer res = StringBuffer();
    await Future.doWhile(() async {
      bool dataReceivedSuccessfully = false;

      //this is used to read all data for specific command line
      while (_socket.available() > 0) {
        res.write(Utf8Codec().decode(_socket.read()!).trim());
        dataReceivedSuccessfully = true;
      }
      if (dataReceivedSuccessfully) return false;

      await Future.delayed(Duration(milliseconds: 300));
      return true;
    }).timeout(
      Duration(seconds: timeout),
      onTimeout: () {
        throw FTPConnectException('Timeout reached for Receiving response !');
      },
    );

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

    try {
      // FTPS starts secure
      if (securityType == SecurityType.ftps) {
        _socket = await RawSecureSocket.connect(
          host,
          port,
          timeout: timeout,
          context: securityContext,
        );
      } else {
        _socket = await RawSocket.connect(host, port, timeout: timeout);
      }
    } catch (e) {
      throw FTPConnectException(
        'Could not connect to $host ($port)',
        e.toString(),
      );
    }

    _hasSocket = true;
    try {
      logger.log('Connection established, waiting for welcome message...');
      final greeting = await readResponse();
      if (greeting.code != 220) {
        throw FTPConnectException('FTP greeting refused', greeting.message);
      }

      // Explicit TLS upgrades after the greeting, before credentials.
      if (securityType == SecurityType.ftpes) {
        final reply = await sendCommand('AUTH TLS');
        if (reply.code != 234) {
          throw FTPConnectException(
            'FTP server refused AUTH TLS',
            reply.message,
          );
        }
        _socket = await RawSecureSocket.secure(
          _socket,
          host: host,
          context: securityContext,
        ).timeout(timeout);
      }

      if (securityType != SecurityType.ftp) {
        for (final command in ['PBSZ 0', 'PROT P']) {
          final reply = await sendCommand(command);
          if (reply.code != 200) {
            throw FTPConnectException(
              'FTP TLS data protection refused',
              reply.message,
            );
          }
        }
      }

      // Send Username
      FTPReply lResp = await sendCommand('USER $user');

      //password required
      if (lResp.code == 331) {
        lResp = await sendCommand('PASS $pass');
        if (lResp.code == 332) {
          if (account == null) throw FTPConnectException('Account required');
          lResp = await sendCommand('ACCT $account');
          if (!lResp.isSuccessCode()) {
            throw FTPConnectException('Wrong Account', lResp.message);
          }
        } else if (!lResp.isSuccessCode()) {
          throw FTPConnectException('Wrong Username/password', lResp.message);
        }
        //account required
      } else if (lResp.code == 332) {
        if (account == null) throw FTPConnectException('Account required');
        lResp = await sendCommand('ACCT $account');
        if (!lResp.isSuccessCode()) {
          throw FTPConnectException('Wrong Account', lResp.message);
        }
      } else if (!lResp.isSuccessCode()) {
        throw FTPConnectException('Wrong username $user', lResp.message);
      }

      logger.log('Connected!');
      return true;
    } catch (_) {
      _hasSocket = false;
      _socket.shutdown(SocketDirection.both);
      await _socket.close();
      rethrow;
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
    if (!_hasSocket) return true;

    try {
      await sendCommand('QUIT');
    } catch (ignored) {
      // Ignore
    } finally {
      _hasSocket = false;
      _socket.shutdown(SocketDirection.both);
      await _socket.close();
    }

    logger.log('Disconnected!');
    return true;
  }
}
