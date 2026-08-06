import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'env.dart';

/// FCM wiring: token registration + notification-tap routing.
///
/// Tapping a DM notification navigates straight into that conversation via
/// [navigatorKey] and the `peer_id` in the data payload.
class PushService {
  PushService(this._api);

  final ApiClient _api;

  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Called by the UI when a notification tap carries a peer_id.
  /// HomeScreen sets this to open the chat room.
  static void Function(String peerId)? onOpenChat;
  static void Function(String broadcastId)? onOpenBroadcast;

  /// Flutter Local Notifications instance for showing OCR alerts.
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: Env.firebaseApiKey,
          appId: Env.firebaseAppId,
          messagingSenderId: Env.firebaseMessagingSenderId,
          projectId: Env.firebaseProjectId,
        ),
      );
    } catch (_) {
      // No Firebase config yet (local dev) — push silently disabled.
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Register the token now and on every rotation
    final token = await messaging.getToken();
    if (token != null) await _registerToken(token);
    messaging.onTokenRefresh.listen(_registerToken);

    // Handle incoming messages (foreground, background, terminated)
    FirebaseMessaging.onMessage.listen(_handleMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) _handleMessage(initialMessage);

    // Initialize local notifications for OCR alerts
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _localNotifications.initialize(initializationSettings);
  }

  Future<void> _registerToken(String token) async {
    try {
      final access = await _api.accessToken;
      if (access == null) return;
      await _api.dio.post<void>(
        '/push/register',
        data: {'token': token},
        options: Options(headers: {'Authorization': 'Bearer $access'}),
      );
    } catch (_) {
      // Retried on next launch / token refresh
    }
  }

  void _handleMessage(RemoteMessage message) {
    final type = message.data['type'];
    if (type == 'ocr_alert') {
      _showOcrAlertNotification(message.data);
    } else {
      // Existing routing for DM and broadcast
      _route(message);
    }
  }

  void _showOcrAlertNotification(Map<String, dynamic> data) {
    final fileId = data['file_id'] as String? ?? 'unknown';
    final keyword = data['keyword'] as String? ?? 'unknown';
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'ocr_alert_channel', // channel id
      'OCR Alerts', // channel name
      channelDescription: 'Notifications for OCR keyword matches',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);
    _localNotifications.show(
      0, // notification id
      'OCR Alert',
      'Keyword "$keyword" found in file $fileId',
      notificationDetails,
      payload: data['file_id'], // optional payload
    );
  }

  void _route(RemoteMessage message) {
    final kind = message.data['kind'];
    if (kind == 'dm') {
      final peerId = message.data['peer_id'];
      if (peerId is String) onOpenChat?.call(peerId);
    } else if (kind == 'broadcast') {
      final id = message.data['broadcast_id'];
      if (id is String) onOpenBroadcast?.call(id);
    }
  }
}