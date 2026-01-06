import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:term_deck/models/ssh_connection.dart';
import 'package:term_deck/theme/app_theme.dart';
import 'package:term_deck/services/shell_history_service.dart';
import 'package:term_deck/widgets/command_input.dart';

class SSHTerminalWidget extends StatefulWidget {
  final SSHConnectionConfig config;
  final String? tmuxSession;
  final VoidCallback? onDisconnect;

  const SSHTerminalWidget({
    super.key,
    required this.config,
    this.tmuxSession,
    this.onDisconnect,
  });

  @override
  State<SSHTerminalWidget> createState() => _SSHTerminalWidgetState();
}

class _SSHTerminalWidgetState extends State<SSHTerminalWidget> {
  late final Terminal _terminal;
  late final ShellHistoryService _historyService;
  SSHClient? _client;
  SSHSession? _session;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final FocusNode _terminalFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _historyService = ShellHistoryService(config: widget.config);
    _connect();
    _historyService.connect();
  }

  Future<void> _connect() async {
    setState(() => _status = ConnectionStatus.connecting);
    _terminal.write('Connecting to ${widget.config.host}...\r\n');

    try {
      final socket = await SSHSocket.connect(
        widget.config.host,
        widget.config.port,
      );

      _client = SSHClient(
        socket,
        username: widget.config.username,
        onPasswordRequest: () => widget.config.password ?? '',
        identities: widget.config.privateKey != null
            ? [...SSHKeyPair.fromPem(widget.config.privateKey!)]
            : null,
      );

      _session = await _client!.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: _terminal.viewWidth,
          height: _terminal.viewHeight,
        ),
      );

      _terminal.buffer.clear();
      _terminal.buffer.setCursor(0, 0);

      setState(() => _status = ConnectionStatus.connected);

      // Handle terminal resize
      _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      // Handle terminal output (user input)
      _terminal.onOutput = (data) {
        _session?.write(utf8.encode(data));
      };

      // Listen to stdout
      _session!.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(
        _terminal.write,
        onDone: _onSessionDone,
      );

      // Listen to stderr
      _session!.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(_terminal.write);

      // Attach to tmux session if specified
      if (widget.tmuxSession != null && widget.tmuxSession!.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        _session!.write(utf8.encode(
            'tmux attach-session -t ${widget.tmuxSession} || tmux new-session -s ${widget.tmuxSession}\n'));
      }
    } catch (e) {
      setState(() => _status = ConnectionStatus.error);
      _terminal.write('\r\n\x1b[31m[Connection failed: $e]\x1b[0m\r\n');
    }
  }

  void _onSessionDone() {
    setState(() => _status = ConnectionStatus.disconnected);
    _terminal.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
    widget.onDisconnect?.call();
  }

  @override
  void dispose() {
    _session?.close();
    _client?.close();
    _historyService.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  void _sendCommand(String command) {
    if (_session == null) return;
    _session!.write(utf8.encode('$command\n'));
  }

  void _focusTerminal() {
    _terminalFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // Responsive font size for terminal
    final screenWidth = MediaQuery.of(context).size.width;
    final terminalFontSize = screenWidth < 600 ? 11.0 : 14.0;

    return Column(
      children: [
        // Terminal area
        Expanded(
          child: Container(
            color: AppColors.base,
            padding: const EdgeInsets.all(4),
            child: Stack(
              children: [
                // TerminalView with GestureDetector for focus handling
                GestureDetector(
                  onTap: _focusTerminal,
                  child: Focus(
                    focusNode: _terminalFocusNode,
                    onKeyEvent: (node, event) {
                      // Pass key events to the terminal
                      return KeyEventResult.ignored;
                    },
                    child: TerminalView(
                      _terminal,
                      textStyle: TerminalStyle(
                        // D2Coding Nerd Font (pre-patched with Nerd Font icons)
                        fontFamily: 'D2CodingNerdFont',
                        // Fallback fonts for Korean character support
                        fontFamilyFallback: const [
                          'Malgun Gothic',
                          'Apple SD Gothic Neo',
                          'Noto Sans KR',
                          'sans-serif',
                        ],
                        fontSize: terminalFontSize,
                        height: 1.2,
                      ),
                      theme: TerminalTheme(
                        cursor: AppColors.rosewater,
                        selection: AppColors.surface2.withValues(alpha: 0.5),
                        foreground: AppColors.text,
                        background: AppColors.base,
                        black: AppColors.surface1,
                        red: AppColors.red,
                        green: AppColors.green,
                        yellow: AppColors.yellow,
                        blue: AppColors.blue,
                        magenta: AppColors.pink,
                        cyan: AppColors.teal,
                        white: AppColors.subtext1,
                        brightBlack: AppColors.surface2,
                        brightRed: AppColors.red,
                        brightGreen: AppColors.green,
                        brightYellow: AppColors.yellow,
                        brightBlue: AppColors.blue,
                        brightMagenta: AppColors.pink,
                        brightCyan: AppColors.teal,
                        brightWhite: AppColors.subtext0,
                        searchHitBackground: AppColors.yellow.withValues(alpha: 0.3),
                        searchHitBackgroundCurrent: AppColors.peach.withValues(alpha: 0.5),
                        searchHitForeground: AppColors.base,
                      ),
                      autofocus: true,
                      alwaysShowCursor: true,
                    ),
                  ),
                ),
                if (_status == ConnectionStatus.connecting)
                  Positioned.fill(
                    child: Container(
                      color: AppColors.base.withValues(alpha: 0.8),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: AppColors.blue,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Connecting...',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Command input area
        if (_status == ConnectionStatus.connected)
          CommandInput(
            historyService: _historyService,
            onSubmit: _sendCommand,
            onFocusTerminal: _focusTerminal,
          ),
      ],
    );
  }
}
