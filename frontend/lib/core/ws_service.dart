import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'env.dart';
import 'outbox_store.dart';

/// Whether the transport is usable, so the interface can say so.
enum WsStatus {
  connected,
  connecting,
  offline,

  /// The server refused this build's protocol version.
  ///
  /// Distinct from `offline` because it is not a network problem and will not
  /// resolve by waiting. Without it an outdated install reconnects forever
  /// into a rejection — draining the battery and telling the user nothing
  /// except that the app is offline, which is not the thing they need to know.
  outdated,
}

/// Real WebSocket transport — ticket handshake then persistent socket.
///
/// Flow: POST /auth/ws-ticket (Bearer) → one-time 30s ticket →
/// connect wss://host/ws/chat?ticket=... → frames stream both ways.
class WsService {
  WsService(this._api, {String? wsBase, OutboxStore? outbox})
      : _wsBase = wsBase ?? Env.wsBaseUrl,
        _outbox = outbox ?? InMemoryOutboxStore();

  final ApiClient _api;
  final String _wsBase;
  final OutboxStore _outbox;

  /// The frame protocol this build speaks.
  ///
  /// Sent at connect and compared server-side. Negotiated once for the
  /// connection rather than stamped on every frame: version belongs to the
  /// conversation, not to each sentence in it.
  static const protocolVersion = 1;

  /// The server's close code for a client it will not serve.
  static const _closedTooOld = 4426;

  WebSocketChannel? _channel;
  final _frames = StreamController<Map<String, dynamic>>.broadcast();
  final _status = StreamController<WsStatus>.broadcast();
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  int _attempt = 0;
  bool _wantConnection = false;
  bool _connecting = false;

  /// Bounded. A device offline for a long time should not accumulate an
  /// unbounded queue, and frames that old are better resent by the user than
  /// delivered as a surprise.
  static const _maxOutbox = 200;

  /// How many reconnects a frame may survive without being acknowledged.
  ///
  /// A backstop, not a delivery policy. The server may legitimately refuse a
  /// frame forever — a message to someone who has blocked the sender is
  /// reported as undeliverable and never acknowledged — and without a cap
  /// that frame is re-sent on every reconnect for the life of the install.
  static const _maxAttempts = 5;

  /// Client refs the queue gave up on, so the interface can mark those
  /// messages failed.
  ///
  /// The previous queue dropped its oldest entry silently when full. That is
  /// the worst possible handling: the frame leaves the outbox while its
  /// optimistic bubble stays in the conversation, still looking sent.
  Stream<String> get dropped => _dropped.stream;
  final _dropped = StreamController<String>.broadcast();

  /// Serialises writes to the store, so two sends in the same tick cannot
  /// interleave and reverse their own order.
  Future<void> _writes = Future.value();

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
    // Called on sign-out, where clearing is right: the queue holds this
    // account's unsent messages and must not survive into the next session.
    // Anything that merely drops the socket must go through
    // _handleDisconnect, which leaves the queue alone.
    await _outbox.clear();
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
          // The transport settles its own queue before handing the frame on.
          //
          // There is a comment above warning against the transport deciding
          // what a frame means, and it still holds — this is not that. Knowing
          // whether its own send completed is exactly a transport's job, and
          // the alternative is every listener having to remember to tell it.
          _settle(frame);
          _frames.add(frame);
        },
        onDone: () {
          // A server that refused the protocol will refuse it again on every
          // attempt. Retrying is not resilience here, it is a loop.
          if (channel.closeCode == _closedTooOld) {
            _wantConnection = false;
            _channel = null;
            _status.add(WsStatus.outdated);
            return;
          }
          _handleDisconnect();
        },
        onError: (_) => _handleDisconnect(),
        cancelOnError: true,
      );

      // Heartbeat keeps the Redis registration alive (server TTL is 90s)
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(
        const Duration(seconds: 45),
        (_) => _write({'type': 'ping'}),
      );

      unawaited(_flushOutbox());
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
  ///
  /// A durable frame is queued **even when the socket is up**. That is the
  /// change that makes this an outbox rather than a buffer: handing bytes to a
  /// sink is not delivery, and a socket that dies between the write and the
  /// server's processing loses the frame with no error on either side. The
  /// entry is removed when the server acknowledges it, not when it is written.
  void send(Map<String, dynamic> frame) {
    if (_isEphemeral(frame['type'] as String?)) {
      if (_channel != null) _write(frame);
      return;
    }

    final raw = jsonEncode(frame);
    final ref = frame['client_ref'] as String?;

    // Chained rather than awaited: `send` is synchronous for its callers, and
    // the chat draws its optimistic bubble immediately. The chain is what
    // keeps two sends in the same tick from reversing their own order.
    _writes = _writes.then((_) async {
      await _outbox.add(raw, clientRef: ref);
      for (final lost in await _outbox.trimTo(_maxOutbox)) {
        _dropped.add(lost);
      }
      if (_channel != null) {
        _write(frame);
      } else if (_wantConnection) {
        // A send is the clearest signal the user expects a live connection.
        await _open();
      }
    });
  }

  /// Removes a queued frame once the server has spoken for it.
  ///
  /// Both outcomes count. An `ack` means stored; an `error` carrying the same
  /// ref means the server refused it and always will — a message to someone
  /// who has blocked the sender, for instance. Treating only the ack would
  /// leave a refused frame re-sending on every reconnect until it exhausted
  /// its attempts, which is five pointless round trips and a delayed failure
  /// the user cannot explain.
  void _settle(Map<String, dynamic> frame) {
    final type = frame['type'];
    if (type != 'ack' && type != 'error') return;

    final ref = frame['client_ref'] as String?;
    if (ref == null) return;

    _writes = _writes.then((_) => _outbox.removeByRef(ref));
    if (type == 'error') _dropped.add(ref);
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

  /// Re-sends everything the server has not acknowledged, oldest first.
  ///
  /// Nothing is removed here. An entry leaves the queue on acknowledgement or
  /// when it runs out of attempts, and re-sending is safe because the server
  /// deduplicates on `client_ref` — see `alembic/versions/0009_message_
  /// idempotency.py`. Without that guarantee this loop would turn every
  /// reconnect into a burst of duplicates.
  Future<void> _flushOutbox() async {
    if (_channel == null) return;

    for (final entry in await _outbox.load()) {
      if (_channel == null) return; // dropped again mid-flush

      if (entry.attempts >= _maxAttempts) {
        await _outbox.removeBySeq(entry.seq);
        if (entry.clientRef != null) _dropped.add(entry.clientRef!);
        continue;
      }

      try {
        _channel!.sink.add(entry.raw);
        await _outbox.countAttempt(entry.seq);
        // A frame with no reference cannot be tracked to an acknowledgement,
        // so best-effort is the best available for it. Every message carries
        // one; this covers the rest.
        if (entry.clientRef == null) await _outbox.removeBySeq(entry.seq);
      } catch (_) {
        return; // socket is gone; the rest stays queued
      }
    }
  }

  // ── Typed helpers ──────────────────────────────────────────────────────────

  /// Sets, changes, or clears this device's reaction to one message.
  ///
  /// A null [content] clears it. There is no separate "unreact" frame, so
  /// there is no second code path that could drift out of step with this one.
  void sendReaction({
    required String target,
    String? to,
    String? group,
    String? content,
    required String clientRef,
  }) =>
      send({
        'type': 'reaction',
        'target': target,
        if (to != null) 'to': to,
        if (group != null) 'group': group,
        if (content != null) 'content': content,
        'client_ref': clientRef,
      });

  void sendText({
    required String to,
    required String content,
    required String clientRef,
    String? replyTo,
  }) =>
      send({
        'type': 'text',
        'to': to,
        'content': content,
        'client_ref': clientRef,
        if (replyTo != null) 'reply_to': replyTo,
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
  WsService.forTest({OutboxStore? outbox})
      : _api = ApiClient(),
        _wsBase = 'ws://test.invalid',
        _outbox = outbox ?? InMemoryOutboxStore();

  /// The queued frames, oldest first. Asynchronous now that the queue is a
  /// table — a test that reads it must await the pending writes first.
  @visibleForTesting
  Future<List<String>> get debugOutbox async {
    await _writes;
    return [for (final entry in await _outbox.load()) entry.raw];
  }

  @visibleForTesting
  Future<void> get debugSettled => _writes;

  @visibleForTesting
  void debugSettle(Map<String, dynamic> frame) => _settle(frame);

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