import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:term_deck/services/shell_history_service.dart';
import 'package:term_deck/theme/app_theme.dart';

class CommandInput extends StatefulWidget {
  final ShellHistoryService historyService;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onFocusTerminal;

  const CommandInput({
    super.key,
    required this.historyService,
    required this.onSubmit,
    this.onFocusTerminal,
  });

  @override
  State<CommandInput> createState() => _CommandInputState();
}

class _CommandInputState extends State<CommandInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isMultiline = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final command = _controller.text;
    if (command.trim().isEmpty) return;

    widget.onSubmit(command);
    widget.historyService.addToHistory(command);
    _controller.clear();
    setState(() => _isMultiline = false);
  }

  bool _isCursorOnFirstLine() {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    if (cursorPos < 0) return true;

    // Check if there's no newline before cursor
    final textBeforeCursor = text.substring(0, cursorPos.clamp(0, text.length));
    return !textBeforeCursor.contains('\n');
  }

  bool _isCursorOnLastLine() {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    if (cursorPos < 0) return true;

    // Check if there's no newline after cursor
    final textAfterCursor = text.substring(cursorPos.clamp(0, text.length));
    return !textAfterCursor.contains('\n');
  }

  void _navigateHistoryUp() {
    widget.historyService.saveCurrentInput(_controller.text);
    final prevCommand = widget.historyService.getPreviousCommand();
    if (prevCommand != null) {
      _controller.text = prevCommand;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: prevCommand.length),
      );
      setState(() => _isMultiline = prevCommand.contains('\n'));
    }
  }

  void _navigateHistoryDown() {
    final nextCommand = widget.historyService.getNextCommand();
    if (nextCommand != null) {
      _controller.text = nextCommand;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: nextCommand.length),
      );
      setState(() => _isMultiline = nextCommand.contains('\n'));
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Enter without shift = submit
    if (key == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _handleSubmit();
      return KeyEventResult.handled;
    }

    // Shift+Enter = newline
    if (key == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isShiftPressed) {
      setState(() => _isMultiline = true);
      return KeyEventResult.ignored;
    }

    // Up arrow at first line = previous history
    if (key == LogicalKeyboardKey.arrowUp && _isCursorOnFirstLine()) {
      _navigateHistoryUp();
      return KeyEventResult.handled;
    }

    // Down arrow at last line = next history
    if (key == LogicalKeyboardKey.arrowDown && _isCursorOnLastLine()) {
      _navigateHistoryDown();
      return KeyEventResult.handled;
    }

    // Escape = focus terminal and unfocus input
    if (key == LogicalKeyboardKey.escape) {
      // Unfocus the command input
      _focusNode.unfocus();
      // Delay slightly to ensure unfocus completes before focusing terminal
      Future.delayed(const Duration(milliseconds: 10), () {
        widget.onFocusTerminal?.call();
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.mantle,
        border: Border(
          top: BorderSide(color: AppColors.surface1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Command input
          Expanded(
            child: Focus(
              onKeyEvent: _handleKeyEvent,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: _isMultiline ? 5 : 1,
                minLines: 1,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontFamily: 'D2CodingNerdFont',
                ),
                decoration: InputDecoration(
                  hintText: 'Enter command... (Shift+Enter for multiline)',
                  hintStyle: TextStyle(
                    color: AppColors.overlay0,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: AppColors.base,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.surface1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.surface1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.blue),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _isMultiline = value.contains('\n'));
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          IconButton(
            onPressed: _handleSubmit,
            icon: const Icon(Icons.send, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.blue,
              foregroundColor: AppColors.base,
              padding: const EdgeInsets.all(10),
            ),
            tooltip: 'Send (Enter)',
          ),
        ],
      ),
    );
  }
}
