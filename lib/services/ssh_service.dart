import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:term_deck/models/ssh_connection.dart';

class SSHService {
  SSHClient? _client;
  SSHSession? _session;
  ConnectionStatus _status = ConnectionStatus.disconnected;

  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;

  final _outputController = StreamController<String>.broadcast();
  Stream<String> get outputStream => _outputController.stream;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  Future<void> connect(SSHConnectionConfig config) async {
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected) {
      return;
    }

    _setStatus(ConnectionStatus.connecting);

    try {
      final socket = await SSHSocket.connect(config.host, config.port);

      _client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password ?? '',
        identities: config.privateKey != null
            ? [
                ...SSHKeyPair.fromPem(config.privateKey!),
              ]
            : null,
      );

      _session = await _client!.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: 80,
          height: 24,
        ),
      );

      _setStatus(ConnectionStatus.connected);

      // Listen to stdout
      _session!.stdout.listen(
        (data) {
          _outputController.add(utf8.decode(data));
        },
        onError: (error) {
          _outputController.addError(error);
        },
        onDone: () {
          disconnect();
        },
      );

      // Listen to stderr
      _session!.stderr.listen(
        (data) {
          _outputController.add(utf8.decode(data));
        },
      );
    } catch (e) {
      _setStatus(ConnectionStatus.error);
      _outputController.addError(e);
      rethrow;
    }
  }

  void write(String data) {
    if (_session != null && isConnected) {
      _session!.stdin.add(utf8.encode(data));
    }
  }

  void resize(int width, int height) {
    if (_session != null && isConnected) {
      _session!.resizeTerminal(width, height);
    }
  }

  Future<void> disconnect() async {
    if (_status == ConnectionStatus.disconnected) return;

    _session?.close();
    _client?.close();

    _session = null;
    _client = null;

    _setStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _outputController.close();
    _statusController.close();
  }
}

class SFTPService {
  final SSHClient _client;
  SftpClient? _sftp;

  SFTPService(this._client);

  Future<void> init() async {
    _sftp = await _client.sftp();
  }

  Future<List<SftpName>> listDirectory(String path) async {
    if (_sftp == null) await init();
    return await _sftp!.listdir(path);
  }

  Future<Uint8List> readFile(String path) async {
    if (_sftp == null) await init();
    final file = await _sftp!.open(path);
    final content = await file.readBytes();
    await file.close();
    return content;
  }

  Future<void> writeFile(String path, Uint8List data) async {
    if (_sftp == null) await init();
    final file = await _sftp!.open(
      path,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    await file.writeBytes(data);
    await file.close();
  }

  Future<void> deleteFile(String path) async {
    if (_sftp == null) await init();
    await _sftp!.remove(path);
  }

  Future<void> deleteDirectory(String path) async {
    if (_sftp == null) await init();
    await _sftp!.rmdir(path);
  }

  Future<void> createDirectory(String path) async {
    if (_sftp == null) await init();
    await _sftp!.mkdir(path);
  }

  Future<String> realPath(String path) async {
    if (_sftp == null) await init();
    return await _sftp!.absolute(path);
  }

  void close() {
    _sftp?.close();
  }
}
