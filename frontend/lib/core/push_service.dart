import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

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

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // No google-services.json yet (local dev) — push silently disabled.
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Register the token now and on every rotation
    final token = await messaging.getToken();
    if (token != null) await _registerToken(token);
    messaging.onTokenRefresh.listen(_registerToken);

    // App opened from a terminated state via notification
    final initial = await messaging.getInitialMessage();
    if (initial != null) _route(initial);

    // App in background, brought forward by tap
    FirebaseMessaging.onMessageOpenedApp.listen(_route);
  }

  Future<void> _registerToken(String token) async {
    try {
      final access = await _api.accessToken;
      if (access == null) return;
      await _api.dio.post<void>(
        '/broadcasts/fcm-token',
        data: {'token': token},
        options: Options(headers: {'Authorization': 'Bearer $access'}),
      );
    } catch (_) {
      // Retried on next launch / token refresh
    }
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
