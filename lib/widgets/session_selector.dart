import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:term_deck/models/ssh_connection.dart';
import 'package:term_deck/services/notification_service.dart';
import 'package:term_deck/theme/app_theme.dart';

class TmuxSession {
  final String name;
  final int windows;
  final String created;
  final bool attached;

  TmuxSession({
    required this.name,
    required this.windows,
    required this.created,
    required this.attached,
  });
}

class SessionSelector extends StatefulWidget {
  final SSHConnectionConfig config;
  final String? selectedSession;
  final ValueChanged<String?> onSessionSelected;

  const SessionSelector({
    super.key,
    required this.config,
    this.selectedSession,
    required this.onSessionSelected,
  });

  @override
  State<SessionSelector> createState() => _SessionSelectorState();
}

class _SessionSelectorState extends State<SessionSelector> with AutomaticKeepAliveClientMixin {
  List<TmuxSession> _sessions = [];
  bool _loading = false;
  String? _error;
  bool _isInitialized = false;
  final _newSessionController = TextEditingController();
  final _notificationService = NotificationService();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Only load sessions if not already initialized (cache check)
    if (!_isInitialized) {
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    debugPrint('[SessionSelector] Starting to load sessions...');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      debugPrint('[SessionSelector] Connecting to ${widget.config.host}:${widget.config.port}...');

      final socket = await SSHSocket.connect(
        widget.config.host,
        widget.config.port,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[SessionSelector] Connection timeout');
          throw TimeoutException('SSH connection timeout (10s)');
        },
      );

      debugPrint('[SessionSelector] Creating SSH client...');
      final client = SSHClient(
        socket,
        username: widget.config.username,
        onPasswordRequest: () => widget.config.password ?? '',
        identities: widget.config.privateKey != null
            ? [...SSHKeyPair.fromPem(widget.config.privateKey!)]
            : null,
      );

      debugPrint('[SessionSelector] Running tmux list-sessions...');
      final result = await client.run(
        'tmux list-sessions -F "#{session_name}|#{session_windows}|#{session_created}|#{session_attached}" 2>/dev/null || echo ""'
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[SessionSelector] Tmux command timeout');
          throw TimeoutException('Tmux command timeout (10s)');
        },
      );

      final output = utf8.decode(result);
      debugPrint('[SessionSelector] Tmux output: $output');

      final sessions = <TmuxSession>[];
      for (final line in output.trim().split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 4) {
          sessions.add(TmuxSession(
            name: parts[0],
            windows: int.tryParse(parts[1]) ?? 0,
            created: parts[2],
            attached: parts[3] == '1',
          ));
        }
      }

      debugPrint('[SessionSelector] Found ${sessions.length} sessions');
      client.close();

      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
        _isInitialized = true; // Mark as initialized after successful load
      });
    } catch (e) {
      debugPrint('[SessionSelector] Error loading sessions: $e');
      if (!mounted) return;
      setState(() {
        _error = 'SSH connection failed: ${e.toString()}';
        _loading = false;
        // Don't mark as initialized on error, allow retry
      });
    }
  }

  Future<void> _saveLastSession(String? session) async {
    final prefs = await SharedPreferences.getInstance();
    if (session != null) {
      await prefs.setString('last_tmux_session', session);
    } else {
      await prefs.remove('last_tmux_session');
    }
  }

  void _selectSession(String? session) {
    _saveLastSession(session);
    _notificationService.clearSessionNotificationCount(session);
    widget.onSessionSelected(session);
  }

  Future<void> _createSession() async {
    final name = _newSessionController.text.trim();
    if (name.isEmpty) return;

    _newSessionController.clear();
    _selectSession(name);
  }

  @override
  void dispose() {
    _newSessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // New session input with solid background
        Container(
          color: AppColors.mantle,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newSessionController,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: 'New session name',
                    hintStyle: TextStyle(
                      color: AppColors.overlay0,
                      fontSize: 12,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surface0,
                  ),
                  onSubmitted: (_) => _createSession(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: _createSession,
                tooltip: 'Create new session',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.green,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loadSessions,
                tooltip: 'Refresh sessions',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.blue,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.surface1),
        // Session list
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.blue,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                'Failed to load sessions',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                style: TextStyle(
                  color: AppColors.subtext0,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadSessions,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.blue,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, color: AppColors.overlay0, size: 32),
            const SizedBox(height: 8),
            Text(
              'No tmux sessions',
              style: TextStyle(color: AppColors.subtext0, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<Map<String, int>>(
      stream: _notificationService.notificationCounts,
      initialData: const {},
      builder: (context, snapshot) {
        final notificationCounts = snapshot.data ?? {};

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _sessions.length + 1, // +1 for "No session" option
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildSessionTile(
                name: 'No tmux session',
                subtitle: 'Direct shell connection',
                icon: Icons.terminal,
                isSelected: widget.selectedSession == null,
                onTap: () => _selectSession(null),
              );
            }

            final session = _sessions[index - 1];
            final notificationCount = notificationCounts[session.name] ?? 0;

            return _buildSessionTile(
              name: session.name,
              subtitle: '${session.windows} window${session.windows != 1 ? 's' : ''}${session.attached ? ' (attached)' : ''}',
              icon: Icons.window,
              isSelected: widget.selectedSession == session.name,
              isAttached: session.attached,
              notificationCount: notificationCount,
              onTap: () => _selectSession(session.name),
            );
          },
        );
      },
    );
  }

  Widget _buildSessionTile({
    required String name,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    bool isAttached = false,
    int notificationCount = 0,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        icon,
        size: 18,
        color: isSelected ? AppColors.blue : AppColors.overlay0,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: isSelected ? AppColors.blue : AppColors.text,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (notificationCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              child: Text(
                notificationCount > 99 ? '99+' : '$notificationCount',
                style: const TextStyle(
                  color: AppColors.crust,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppColors.subtext0,
          fontSize: 11,
        ),
      ),
      trailing: isAttached
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'active',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 10,
                ),
              ),
            )
          : null,
      selected: isSelected,
      selectedTileColor: AppColors.surface0.withValues(alpha: 0.5),
      onTap: onTap,
    );
  }
}
