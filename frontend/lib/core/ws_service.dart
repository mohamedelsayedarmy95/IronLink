import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'env.dart';

/// Real WebSocket transport — ticket handshake then persistent socket.
///
/// Flow: POST /auth/ws-ticket (Bearer) → one-time 30s ticket →
/// connect wss://host/ws/chat?ticket=... → frames stream both ways.
class WsService {
  WsService(this._api, {String? wsBase}) : _wsBase = wsBase ?? Env.wsBaseUrl;

  final ApiClient _api;
  final String _wsBase;

  WebSocketChannel? _channel;
  final _frames = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _pingTimer;

  Stream<Map<String, dynamic>> get frames => _frames.stream;
  bool get isConnected => _channel != null;

  Future<void> connect() async {
    final res =
        await _api.authedPost<Map<String, dynamic>>('/auth/ws-ticket');
    final ticket = res.data!['ticket'] as String;

    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBase/ws/chat?ticket=$ticket'),
    );

    _channel!.stream.listen(
      (raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        _frames.add(frame);
      },
      onDone: _handleDisconnect,
      onError: (_) => _handleDisconnect(),
    );

    // Heartbeat keeps the Redis registration alive (server TTL is 90s)
    _pingTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => send({'type': 'ping'}),
    );
  }

  void send(Map<String, dynamic> frame) {
    _channel?.sink.add(jsonEncode(frame));
  }

  // ── Typed helpers ──────────────────────────────────────────────────────────

  void sendText({
    required String to,
    required String content,
    required String clientRef,
  }) =>
      send({
        'type': 'text',
        'to': to,
        'content': content,
        'client_ref': clientRef,
      });

  void sendMedia({
    required String to,
    required String kind, // 'image' | 'file'
    required String mediaKey,
    required String mimeType,
    String? caption,
    required String clientRef,
  }) =>
      send({
        'type': kind,
        'to': to,
        'media_key': mediaKey,
        'media_mime': mimeType,
        'content': caption,
        'client_ref': clientRef,
      });

  void sendTyping({required String to, required bool typing}) =>
      send({'type': typing ? 'typing_start' : 'typing_stop', 'to': to});

  void sendRead(String messageId) =>
      send({'type': 'message_read', 'message_id': messageId});

  void sendDelivered(String messageId) =>
      send({'type': 'message_delivered', 'message_id': messageId});

  void unsend(String messageId) =>
      send({'type': 'unsend', 'message_id': messageId});

  void _handleDisconnect() {
    _pingTimer?.cancel();
    _channel = null;
    _frames.add({'type': '_disconnected'});
  }

  Future<void> dispose() async {
    _pingTimer?.cancel();
    await _channel?.sink.close();
    await _frames.close();
  }
}
