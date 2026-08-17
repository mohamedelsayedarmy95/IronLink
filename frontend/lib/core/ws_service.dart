import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'env.dart';

/// Whether the transport is usable, so the interface can say so.
enum WsStatus { connected, connecting, offline }

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
  final _status = StreamController<WsStatus>.broadcast();
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  int _attempt = 0;
  bool _wantConnection = false;
  bool _connecting = false;

  /// Frames written while the socket was down, replayed in order on
  /// reconnect.
  ///
  /// Without it `send` was `_channel?.sink.add(...)` — a null-aware call that
  /// silently did nothing when disconnected. The chat still drew the
  /// optimistic bubble, so a message typed on a dropped connection looked
  /// sent and was simply gone. On a phone that is not a rare case: it happens
  /// on every WiFi-to-mobile handover.
  final _outbox = <String>[];

  /// Bounded. A device offline for a long time should not accumulate
  /// unbounded memory, and frames that old are better resent by the user
  /// than delivered as a surprise.
  static const _maxOutbox = 200;

  Stream<Map<String, dynamic>> get frames => _frames.stream;

  /// So the interface can say "connecting" rather than looking idle while
  /// nothing works.
  Stream<WsStatus> get status => _status.stream;

  bool get isConnected => _channel != null;

  /// Opens the socket and keeps it open until [disconnect].
  Future<void> connect() async {
    _wantConnection = true;
    await _open();
  }

  /// Stops reconnecting. Called on sign-out.
  Future<void> disconnect() async {
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _outbox.clear();
    await _channel?.sink.close();
    _channel = null;
    _status.add(WsStatus.offline);
  }

  Future<void> _open() async {
    if (_connecting || _channel != null || !_wantConnection) return;
    _connecting = true;
    _status.add(WsStatus.connecting);

    try {
      final res =
          await _api.authedPost<Map<String, dynamic>>('/auth/ws-ticket');
      final ticket = res.data!['ticket'] as String;

      final channel = WebSocketChannel.connect(
        Uri.parse('$_wsBase/ws/chat?ticket=$ticket'),
      );
      // Waits for the handshake, so a failure to connect is caught here
      // rather than surfacing as a stream error after we have already
      // reported success.
      await channel.ready;

      _channel = channel;
      _attempt = 0;
      _status.add(WsStatus.connected);

      channel.stream.listen(
        (raw) {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          // Every frame goes to one stream and nowhere else. This used to
          // special-case 'ocr_alert' and push it into a singleton bloc, which
          // meant one frame type bypassed the stream every other listener
          // reads — and after the alert feature moved on-device, it pushed
          // into a bloc nothing rendered. A transport should carry frames, not
          // decide what they mean.
          _frames.add(frame);
        },
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
        cancelOnError: true,
      );

      // Heartbeat keeps the Redis registration alive (server TTL is 90s)
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(
        const Duration(seconds: 45),
        (_) => _write({'type': 'ping'}),
      );

      _flushOutbox();
    } catch (_) {
      _channel = null;
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  /// Exponential backoff with jitter, capped.
  ///
  /// The jitter matters at the scale a server restart operates on: without
  /// it every client that dropped together comes back together, and the
  /// reconnect storm is what keeps the server down.
  void _scheduleReconnect() {
    if (!_wantConnection) return;
    _reconnectTimer?.cancel();
    _status.add(WsStatus.offline);
    _reconnectTimer = Timer(_nextBackoff(), _open);
  }

  Duration _nextBackoff() {
    final backoff = _baseDelay * (1 << _attempt.clamp(0, 5));
    final capped = backoff > _maxDelay ? _maxDelay : backoff;
    _attempt++;
    return capped +
        Duration(milliseconds: _random.nextInt(capped.inMilliseconds ~/ 2 + 1));
  }

  static const _baseDelay = Duration(seconds: 1);
  static const _maxDelay = Duration(seconds: 30);
  static final _random = Random();

  /// Queues durable frames, drops ephemeral ones.
  ///
  /// A typing indicator or a heartbeat replayed minutes later is noise; a
  /// message is not.
  void send(Map<String, dynamic> frame) {
    if (_channel != null) {
      _write(frame);
      return;
    }

    if (_isEphemeral(frame['type'] as String?)) return;

    if (_outbox.length >= _maxOutbox) _outbox.removeAt(0);
    _outbox.add(jsonEncode(frame));
    // A send is the clearest signal the user expects a live connection.
    if (_wantConnection) _open();
  }

  static bool _isEphemeral(String? type) =>
      type == 'ping' ||
      type == 'typing_start' ||
      type == 'typing_stop' ||
      type == 'presence';

  void _write(Map<String, dynamic> frame) {
    try {
      _channel?.sink.add(jsonEncode(frame));
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _flushOutbox() {
    if (_outbox.isEmpty || _channel == null) return;
    // Copied first: a failed write re-enters _handleDisconnect, which must
    // not mutate the list being iterated.
    final pending = List<String>.from(_outbox);
    _outbox.clear();
    for (final raw in pending) {
      try {
        _channel!.sink.add(raw);
      } catch (_) {
        _outbox.add(raw);
      }
    }
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

  /// A group message. One ciphertext for the whole group — the server fans
  /// the same bytes out to every member.
  void sendGroupText({
    required String group,
    required String content,
    required String clientRef,
  }) =>
      send({
        'type': 'group_text',
        'group': group,
        'content': content,
        'client_ref': clientRef,
      });

  /// A group attachment or voice note.
  ///
  /// The pointer, the caption and the key that opens the body all live inside
  /// [content] — the group envelope — so the server cannot tell which stored
  /// object this refers to. media_key is deliberately not sent alongside.
  void sendGroupMedia({
    required String group,
    required String kind, // 'image' | 'file' | 'voice'
    required String content,
    required String clientRef,
  }) =>
      send({
        'type': 'group_$kind',
        'group': group,
        'content': content,
        'client_ref': clientRef,
      });

  /// A sender-key distribution message, pairwise encrypted for one member.
  ///
  /// Separate from sendText so it can never be mistaken for something the
  /// sender said: it is key material and is filtered out of history.
  void sendSenderKey({
    required String group,
    required String to,
    required String content,
    required String clientRef,
  }) =>
      send({
        'type': 'skdm',
        'group': group,
        'to': to,
        'content': content,
        'client_ref': clientRef,
      });

  void sendTyping({required String to, required bool typing}) =>
      send({'type': typing ? 'typing_start' : 'typing_stop', 'to': to});

  void sendRead(String messageId) =>
      send({'type': 'read', 'message_id': messageId});

  void sendDelivered(String messageId) =>
      send({'type': 'delivered', 'message_id': messageId});

  // ── Test surface ───────────────────────────────────────────────────────────
  //
  // A transport cannot be exercised without a socket, and the queueing and
  // backoff rules are exactly the part worth testing: they decide whether a
  // message survives a network handover. This is the smallest hole that lets
  // those rules be checked, and it opens nothing a caller would misuse — the
  // members are inert without a connection.

  @visibleForTesting
  WsService.forTest()
      : _api = ApiClient(),
        _wsBase = 'ws://test.invalid';

  @visibleForTesting
  List<String> get debugOutbox => List.unmodifiable(_outbox);

  @visibleForTesting
  set debugWantConnection(bool value) => _wantConnection = value;

  @visibleForTesting
  bool get debugReconnectScheduled => _reconnectTimer?.isActive ?? false;

  @visibleForTesting
  void debugHandleDisconnect() => _handleDisconnect();

  @visibleForTesting
  Duration debugNextBackoff() => _nextBackoff();

  void unsend(String messageId) =>
      send({'type': 'unsend', 'message_id': messageId});

  void _handleDisconnect() {
    _pingTimer?.cancel();
    _channel = null;
    _frames.add({'type': '_disconnected'});
    // This used to be the end of it: the socket dropped, a frame nobody
    // listened for was emitted, and the app stayed silently offline until it
    // was killed and reopened.
    _scheduleReconnect();
  }

  Future<void> dispose() async {
    _pingTimer?.cancel();
    await _channel?.sink.close();
    await _frames.close();
  }
}