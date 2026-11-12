import 'dart:async';
import 'dart:convert';

import '../ftp_entry.dart';
import '../ftp_exceptions.dart';
import '../ftp_reply.dart';
import '../ftp_socket.dart';
import '../ftpconnect_base.dart';
import '../utils.dart';

class FTPDirectory {
  final FTPSocket _socket;

  FTPDirectory(this._socket);

  Future<bool> makeDirectory(String sName) async {
    FTPReply sResponse = await (_socket.sendCommand('MKD $sName'));

    return sResponse.isSuccessCode();
  }

  Future<bool> deleteEmptyDirectory(String? sName) async {
    FTPReply sResponse = await (_socket.sendCommand('rmd $sName'));

    return sResponse.isSuccessCode();
  }

  Future<bool> changeDirectory(String? sName) async {
    FTPReply sResponse = await (_socket.sendCommand('CWD $sName'));

    return sResponse.isSuccessCode();
  }

  Future<String> currentDirectory() async {
    FTPReply sResponse = await _socket.sendCommand('PWD');
    if (!sResponse.isSuccessCode()) {
      throw FTPConnectException(
        'Failed to get current working directory',
        sResponse.message,
      );
    }

    int iStart = sResponse.message.indexOf('"') + 1;
    int iEnd = sResponse.message.lastIndexOf('"');

    return sResponse.message.substring(iStart, iEnd);
  }

  Future<List<FTPEntry>> directoryContent() async {
    // Enter passive mode
    FTPReply response = await _socket.openDataTransferChannel();

    // Directoy content listing, the response will be handled by another socket
    _socket.sendCommandWithoutWaitingResponse(_socket.listCommand.describeEnum);

    // Data transfer socket
    int iPort = Utils.parsePort(response.message, _socket.supportIPV6);
    final dataConnection = await _socket.openDataSocket(iPort);
    try {
      // Test if the second socket connection was accepted.
      response = await _socket.readResponse();
      // Some servers return both 125 and 226 for a completed transfer.
      bool isTransferCompleted = response.isSuccessCode();
      if (!isTransferCompleted &&
          response.code != 125 &&
          response.code != 150) {
        throw FTPConnectException('Connection refused. ', response.message);
      }
      final dataSocket = await _socket.protectDataSocket(dataConnection);
      final lstDirectoryListing = <int>[];
      await for (final data
          in dataSocket.timeout(Duration(seconds: _socket.timeout))) {
        lstDirectoryListing.addAll(data);
      }
      await dataSocket.close();

      if (!isTransferCompleted) {
        response = await _socket.readResponse();
        if (!response.isSuccessCode()) {
          throw FTPConnectException('Transfer Error.', response.message);
        }
      }

      // Convert MLSD response into FTPEntry.
      return [
        for (final line in Utf8Codec().decode(lstDirectoryListing).split('\n'))
          if (line.trim().isNotEmpty)
            FTPEntry.parse(line.replaceAll('\r', ''), _socket.listCommand),
      ];
    } finally {
      _socket.closeDataSocket(dataConnection);
    }
  }

  Future<List<String>> directoryContentNames() async {
    var list = await directoryContent();
    return list.map((f) => f.name).whereType<String>().toList();
  }
}
