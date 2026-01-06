import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:term_deck/models/ssh_connection.dart';

enum ShellType { bash, zsh, fish, unknown }

class ShellHistoryService {
  final SSHConnectionConfig config;
  SSHClient? _client;
  SftpClient? _sftp;
  ShellType _shellType = ShellType.unknown;
  List<String> _history = [];
  int _historyIndex = -1;
  String _currentInput = '';

  ShellHistoryService({required this.config});

  List<String> get history => _history;
  int get historyIndex => _historyIndex;
  ShellType get shellType => _shellType;

  Future<void> connect() async {
    try {
      final socket = await SSHSocket.connect(config.host, config.port);
      _client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password ?? '',
        identities: config.privateKey != null
            ? [...SSHKeyPair.fromPem(config.privateKey!)]
            : null,
      );
      _sftp = await _client!.sftp();
      await _detectShell();
      await _loadHistory();
    } catch (e) {
      // Silently fail - history is optional feature
    }
  }

  Future<void> _detectShell() async {
    if (_client == null) return;

    try {
      final result = await _client!.run('echo \$SHELL');
      final shell = utf8.decode(result).trim().toLowerCase();

      if (shell.contains('zsh')) {
        _shellType = ShellType.zsh;
      } else if (shell.contains('bash')) {
        _shellType = ShellType.bash;
      } else if (shell.contains('fish')) {
        _shellType = ShellType.fish;
      } else {
        _shellType = ShellType.unknown;
      }
    } catch (e) {
      _shellType = ShellType.unknown;
    }
  }

  String get _historyFilePath {
    final home = '/home/${config.username}';
    return switch (_shellType) {
      ShellType.zsh => '$home/.zsh_history',
      ShellType.bash => '$home/.bash_history',
      ShellType.fish => '$home/.local/share/fish/fish_history',
      ShellType.unknown => '$home/.bash_history',
    };
  }

  Future<void> _loadHistory() async {
    if (_sftp == null) return;

    try {
      final file = await _sftp!.open(_historyFilePath);
      final bytes = await file.readBytes();
      await file.close();

      final content = utf8.decode(bytes);
      _history = _parseHistory(content);
      _historyIndex = _history.length;
    } catch (e) {
      _history = [];
      _historyIndex = 0;
    }
  }

  List<String> _parseHistory(String content) {
    final lines = content.split('\n');
    final commands = <String>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      String command;
      if (_shellType == ShellType.zsh) {
        // zsh format: ": timestamp:0;command" or just "command"
        if (line.startsWith(':') && line.contains(';')) {
          final semicolonIndex = line.indexOf(';');
          command = line.substring(semicolonIndex + 1);
        } else {
          command = line;
        }
      } else if (_shellType == ShellType.fish) {
        // fish format: "- cmd: command"
        if (line.startsWith('- cmd:')) {
          command = line.substring(7).trim();
        } else {
          continue;
        }
      } else {
        // bash: plain text
        command = line;
      }

      if (command.trim().isNotEmpty) {
        commands.add(command.trim());
      }
    }

    // Return last 500 commands (most recent)
    if (commands.length > 500) {
      return commands.sublist(commands.length - 500);
    }
    return commands;
  }

  /// Called when user starts typing - saves current input
  void saveCurrentInput(String input) {
    if (_historyIndex == _history.length) {
      _currentInput = input;
    }
  }

  /// Navigate to previous command (up arrow)
  String? getPreviousCommand() {
    if (_history.isEmpty) return null;

    if (_historyIndex > 0) {
      _historyIndex--;
      return _history[_historyIndex];
    }
    return null;
  }

  /// Navigate to next command (down arrow)
  String? getNextCommand() {
    if (_history.isEmpty) return null;

    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      return _history[_historyIndex];
    } else if (_historyIndex == _history.length - 1) {
      _historyIndex = _history.length;
      return _currentInput;
    }
    return null;
  }

  /// Reset history index to end (for new input)
  void resetHistoryIndex() {
    _historyIndex = _history.length;
    _currentInput = '';
  }

  /// Add command to local history
  void addToHistory(String command) {
    if (command.trim().isEmpty) return;

    // Don't add duplicates of the last command
    if (_history.isNotEmpty && _history.last == command.trim()) return;

    _history.add(command.trim());
    resetHistoryIndex();
  }

  /// Reload history from server
  Future<void> refreshHistory() async {
    await _loadHistory();
  }

  void dispose() {
    _sftp?.close();
    _client?.close();
  }
}
