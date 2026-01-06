import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:term_deck/screens/connection_screen.dart';
import 'package:term_deck/services/notification_service.dart';
import 'package:term_deck/theme/app_theme.dart';
import 'package:term_deck/widgets/toast_overlay.dart';

// Default backend URL (can be overridden in settings)
const String defaultBackendUrl = 'http://100.82.190.41:20030';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.crust,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Start app immediately, initialize notifications in background
  runApp(
    const ProviderScope(
      child: SSHTerminalApp(),
    ),
  );

  // Initialize notification service after app starts (non-blocking)
  Future.delayed(const Duration(seconds: 1), () {
    NotificationService().initialize(backendUrl: defaultBackendUrl);
  });
}

class SSHTerminalApp extends StatelessWidget {
  const SSHTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermDeck',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ToastOverlay(
        child: ConnectionScreen(),
      ),
    );
  }
}
