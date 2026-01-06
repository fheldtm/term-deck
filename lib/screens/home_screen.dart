import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:term_deck/models/ssh_connection.dart';
import 'package:term_deck/theme/app_theme.dart';
import 'package:term_deck/widgets/terminal_view.dart' as tv;
import 'package:term_deck/widgets/session_selector.dart';
import 'package:term_deck/widgets/file_explorer.dart';
import 'package:term_deck/screens/connection_screen.dart';
import 'package:term_deck/services/toast_service.dart';

class HomeScreen extends StatefulWidget {
  final SSHConnectionConfig config;

  const HomeScreen({super.key, required this.config});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SSHConnectionConfig _config;

  String? _selectedSession;
  bool _isConnected = false;
  String? _currentPath;

  // Sidebar state
  double _sidebarWidth = 280;

  // Terminal key for reconnection
  Key _terminalKey = UniqueKey();

  // Drawer key for mobile
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // GlobalKeys to preserve widget state (desktop sidebar)
  final GlobalKey _desktopSessionSelectorKey = GlobalKey();
  final GlobalKey _desktopFileExplorerKey = GlobalKey();

  // GlobalKeys to preserve widget state (mobile drawer)
  final GlobalKey _mobileSessionSelectorKey = GlobalKey();
  final GlobalKey _mobileFileExplorerKey = GlobalKey();

  // Drawer visibility state (for mobile)
  bool _isDrawerVisible = false;

  // Breakpoint for mobile/desktop
  static const double _mobileBreakpoint = 600;

  // Back press tracking for app exit
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _loadLastSession();
  }

  Future<void> _loadLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSession = prefs.getString('last_tmux_session');
    if (lastSession != null) {
      setState(() => _selectedSession = lastSession);
    }
    // Auto-connect on start
    setState(() => _isConnected = true);
  }

  void _onSessionSelected(String? session) {
    setState(() {
      _selectedSession = session;
      _terminalKey = UniqueKey(); // Force terminal reconnection
    });
    // Close drawer on mobile after selection
    _closeDrawer();
  }

  void _openDrawer() {
    setState(() => _isDrawerVisible = true);
  }

  void _closeDrawer() {
    setState(() => _isDrawerVisible = false);
  }

  void _reconnect() {
    setState(() {
      _terminalKey = UniqueKey();
      _isConnected = true;
    });
  }

  void _disconnect() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ConnectionScreen()),
    );
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < _mobileBreakpoint;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Check if drawer is visible
        if (_isDrawerVisible) {
          _closeDrawer();
          return;
        }

        // Handle app exit confirmation
        final now = DateTime.now();
        if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ToastService().info('뒤로 가기를 한번 더 누르면 종료됩니다');
          return;
        }

        // Exit app
        SystemNavigator.pop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.base,
        appBar: isMobile ? _buildMobileAppBar() : null,
        body: Stack(
          children: [
            // Main body
            isMobile ? _buildMobileBody() : _buildDesktopBody(),

            // Persistent drawer (mobile only, hidden with Offstage)
            if (isMobile)
              Offstage(
                offstage: !_isDrawerVisible,
                child: _buildDrawer(),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar() {
    return AppBar(
      backgroundColor: AppColors.mantle,
      title: Text(
        _selectedSession ?? 'SSH Terminal',
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 16,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.menu, color: AppColors.subtext0),
        onPressed: _openDrawer,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: AppColors.subtext0),
          onPressed: _disconnect,
          tooltip: 'Disconnect',
        ),
        if (!_isConnected)
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.blue),
            onPressed: _reconnect,
            tooltip: 'Reconnect',
          ),
      ],
    );
  }

  Widget _buildDrawer() {
    return GestureDetector(
      onTap: _closeDrawer,
      child: Container(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {}, // Prevent taps from closing drawer
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: MediaQuery.of(context).size.width,
              color: AppColors.mantle,
              child: Column(
                children: [
                  // Header with proper status bar padding
                  Container(
                    color: AppColors.crust,
                    child: SafeArea(
                      bottom: false,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.surface1),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.terminal, color: AppColors.blue, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'SSH Terminal',
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${_config.username}@${_config.host}',
                                    style: const TextStyle(
                                      color: AppColors.subtext0,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Tab content area
                  Expanded(
                    child: _DrawerContent(
                      config: _config,
                      selectedSession: _selectedSession,
                      currentPath: _currentPath,
                      onSessionSelected: _onSessionSelected,
                      onPathChange: (path) => setState(() => _currentPath = path),
                      sessionSelectorKey: _mobileSessionSelectorKey,
                      fileExplorerKey: _mobileFileExplorerKey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBody() {
    return _isConnected
        ? tv.SSHTerminalWidget(
            key: _terminalKey,
            config: _config,
            tmuxSession: _selectedSession,
            onDisconnect: () {
              setState(() => _isConnected = false);
            },
          )
        : _buildDisconnectedView();
  }

  Widget _buildDesktopBody() {
    return Row(
      children: [
        // Sidebar
        Container(
          width: _sidebarWidth,
          color: AppColors.mantle,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                color: AppColors.crust,
                child: Row(
                  children: [
                    const Icon(Icons.terminal, color: AppColors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_config.username}@${_config.host}',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, size: 18),
                      onPressed: _disconnect,
                      tooltip: 'Disconnect',
                      style: IconButton.styleFrom(foregroundColor: AppColors.subtext0),
                    ),
                  ],
                ),
              ),

              // Tab content area
              Expanded(
                child: _DesktopSidebarContent(
                  config: _config,
                  selectedSession: _selectedSession,
                  currentPath: _currentPath,
                  onSessionSelected: _onSessionSelected,
                  onPathChange: (path) => setState(() => _currentPath = path),
                  sessionSelectorKey: _desktopSessionSelectorKey,
                  fileExplorerKey: _desktopFileExplorerKey,
                ),
              ),
            ],
          ),
        ),

        // Sidebar resize handle
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(200.0, 500.0);
            });
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: Container(
              width: 4,
              color: AppColors.surface1,
            ),
          ),
        ),

        // Main terminal area
        Expanded(
          child: _isConnected
              ? tv.SSHTerminalWidget(
                  key: _terminalKey,
                  config: _config,
                  tmuxSession: _selectedSession,
                  onDisconnect: () {
                    setState(() => _isConnected = false);
                  },
                )
              : _buildDisconnectedView(),
        ),
      ],
    );
  }

  Widget _buildDisconnectedView() {
    return Container(
      color: AppColors.base,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.link_off,
              size: 64,
              color: AppColors.overlay0,
            ),
            const SizedBox(height: 16),
            const Text(
              'Disconnected',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connection to server was lost',
              style: TextStyle(
                color: AppColors.subtext0,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _reconnect,
              icon: const Icon(Icons.refresh),
              label: const Text('Reconnect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: AppColors.base,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Drawer content with tab UI
class _DrawerContent extends StatefulWidget {
  final SSHConnectionConfig config;
  final String? selectedSession;
  final String? currentPath;
  final ValueChanged<String?> onSessionSelected;
  final ValueChanged<String> onPathChange;
  final GlobalKey sessionSelectorKey;
  final GlobalKey fileExplorerKey;

  const _DrawerContent({
    required this.config,
    required this.selectedSession,
    required this.currentPath,
    required this.onSessionSelected,
    required this.onPathChange,
    required this.sessionSelectorKey,
    required this.fileExplorerKey,
  });

  @override
  State<_DrawerContent> createState() => _DrawerContentState();
}

class _DrawerContentState extends State<_DrawerContent> {
  int _selectedTabIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedTabIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          decoration: const BoxDecoration(
            color: AppColors.crust,
            border: Border(
              bottom: BorderSide(color: AppColors.surface1),
            ),
          ),
          child: Row(
            children: [
              _buildTab(
                label: 'SESSIONS',
                index: 0,
                isSelected: _selectedTabIndex == 0,
              ),
              _buildTab(
                label: 'FILES',
                index: 1,
                isSelected: _selectedTabIndex == 1,
              ),
            ],
          ),
        ),

        // Tab content with swipe support
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _selectedTabIndex = index);
            },
            children: [
              SessionSelector(
                key: widget.sessionSelectorKey,
                config: widget.config,
                selectedSession: widget.selectedSession,
                onSessionSelected: widget.onSessionSelected,
              ),
              FileExplorer(
                key: widget.fileExplorerKey,
                config: widget.config,
                currentPath: widget.currentPath,
                onPathChange: widget.onPathChange,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab({
    required String label,
    required int index,
    required bool isSelected,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTabIndex = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface0 : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isSelected ? AppColors.blue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? AppColors.text : AppColors.subtext0,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

// Desktop sidebar content with tab UI
class _DesktopSidebarContent extends StatefulWidget {
  final SSHConnectionConfig config;
  final String? selectedSession;
  final String? currentPath;
  final ValueChanged<String?> onSessionSelected;
  final ValueChanged<String> onPathChange;
  final GlobalKey sessionSelectorKey;
  final GlobalKey fileExplorerKey;

  const _DesktopSidebarContent({
    required this.config,
    required this.selectedSession,
    required this.currentPath,
    required this.onSessionSelected,
    required this.onPathChange,
    required this.sessionSelectorKey,
    required this.fileExplorerKey,
  });

  @override
  State<_DesktopSidebarContent> createState() => _DesktopSidebarContentState();
}

class _DesktopSidebarContentState extends State<_DesktopSidebarContent> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          decoration: const BoxDecoration(
            color: AppColors.crust,
            border: Border(
              bottom: BorderSide(color: AppColors.surface1),
            ),
          ),
          child: Row(
            children: [
              _buildTab(
                label: 'SESSIONS',
                index: 0,
                isSelected: _selectedTabIndex == 0,
              ),
              _buildTab(
                label: 'FILES',
                index: 1,
                isSelected: _selectedTabIndex == 1,
              ),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _selectedTabIndex == 0
                ? SessionSelector(
                    key: widget.sessionSelectorKey,
                    config: widget.config,
                    selectedSession: widget.selectedSession,
                    onSessionSelected: widget.onSessionSelected,
                  )
                : FileExplorer(
                    key: widget.fileExplorerKey,
                    config: widget.config,
                    currentPath: widget.currentPath,
                    onPathChange: widget.onPathChange,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTab({
    required String label,
    required int index,
    required bool isSelected,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface0 : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isSelected ? AppColors.blue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? AppColors.text : AppColors.subtext0,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
