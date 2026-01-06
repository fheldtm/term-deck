import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background message: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? _backendUrl;
  bool _isInitialized = false;

  // Session notification counts
  final Map<String, int> _sessionNotificationCounts = {};
  final _notificationCountsController = StreamController<Map<String, int>>.broadcast();

  String? get fcmToken => _fcmToken;
  bool get isInitialized => _isInitialized;
  Stream<Map<String, int>> get notificationCounts => _notificationCountsController.stream;

  // Notification channel for Android
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'terminal_notifications',
    'Terminal Notifications',
    description: 'Notifications from SSH Terminal',
    importance: Importance.high,
    playSound: true,
  );

  Future<void> initialize({required String backendUrl}) async {
    if (_isInitialized) {
      debugPrint('NotificationService already initialized');
      return;
    }

    _backendUrl = backendUrl;

    try {
      // Initialize Firebase
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request permission
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('Notification permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _setupLocalNotifications();
        await _getAndRegisterToken();
        _setupMessageHandlers();
      }

      _isInitialized = true;
      debugPrint('NotificationService initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize notifications: $e');
      // Continue without notifications - app should still work
      _isInitialized = false;
    }
  }

  Future<void> _setupLocalNotifications() async {
    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channel for Android
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // Handle notification tap - could navigate to specific screen
  }

  Future<void> _getAndRegisterToken() async {
    if (_messaging == null) return;

    try {
      _fcmToken = await _messaging!.getToken();
      debugPrint('FCM Token: ${_fcmToken?.substring(0, 20)}...');

      if (_fcmToken != null && _backendUrl != null) {
        await _registerTokenWithBackend(_fcmToken!);
      }

      // Listen for token refresh
      _messaging!.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        await _registerTokenWithBackend(newToken);
      });
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
    }
  }

  Future<void> _registerTokenWithBackend(String token) async {
    if (_backendUrl == null) return;

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/api/fcm/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      );

      if (response.statusCode == 200) {
        debugPrint('FCM token registered with backend');
      } else {
        debugPrint('Failed to register token: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Failed to register token with backend: $e');
    }
  }

  void _setupMessageHandlers() {
    if (_messaging == null) return;

    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message: ${message.notification?.title}');
      _incrementSessionNotificationCount(message);
      _showLocalNotification(message);
    });

    // When app is opened from background via notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('App opened from notification: ${message.notification?.title}');
      _incrementSessionNotificationCount(message);
      // Handle navigation if needed
    });
  }

  void _incrementSessionNotificationCount(RemoteMessage message) {
    final sessionName = message.data['session_name'] as String?;
    if (sessionName != null && sessionName.isNotEmpty) {
      _sessionNotificationCounts[sessionName] =
          (_sessionNotificationCounts[sessionName] ?? 0) + 1;
      _notificationCountsController.add(Map.from(_sessionNotificationCounts));
      debugPrint('Notification count for session "$sessionName": ${_sessionNotificationCounts[sessionName]}');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  // Show a local notification directly (for WebSocket notifications)
  Future<void> showNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!_isInitialized) {
      debugPrint('Cannot show notification: service not initialized');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: data != null ? jsonEncode(data) : null,
    );
  }

  // Clear notification count for a specific session
  void clearSessionNotificationCount(String? sessionName) {
    if (sessionName != null && _sessionNotificationCounts.containsKey(sessionName)) {
      _sessionNotificationCounts[sessionName] = 0;
      _notificationCountsController.add(Map.from(_sessionNotificationCounts));
      debugPrint('Cleared notification count for session "$sessionName"');
    }
  }

  // Get current notification count for a session
  int getSessionNotificationCount(String? sessionName) {
    if (sessionName == null) return 0;
    return _sessionNotificationCounts[sessionName] ?? 0;
  }

  Future<void> unregisterToken() async {
    if (_fcmToken == null || _backendUrl == null) return;

    try {
      await http.post(
        Uri.parse('$_backendUrl/api/fcm/unregister'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': _fcmToken}),
      );
    } catch (e) {
      debugPrint('Failed to unregister token: $e');
    }
  }

  void dispose() {
    _notificationCountsController.close();
  }
}
