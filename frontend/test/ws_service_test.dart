import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/ws_service.dart';

/// Transport reliability.
///
/// The socket used to be opened once and never reopened: a drop emitted a
/// frame nobody listened for and the app stayed silently offline until it was
/// killed. And `send` was a null-aware call on a possibly-null channel, so a
/// message written while disconnected vanished — while the chat drew an
/// optimistic bubble saying it had been sent.
///
/// On a phone neither is an edge case. Both happen on a WiFi-to-mobile
/// handover.
void main() {
  group('what happens to a message sent while disconnected', () {
    test('it is kept rather than dropped', () {
      final ws = WsService.forTest();

      ws.send({'type': 'text', 'to': 'bob', 'content': 'x', 'client_ref': 'r1'});

      expect(ws.debugOutbox, hasLength(1),
          reason: 'a message written offline must survive to be sent');
    });

    test('order is preserved', () {
      final ws = WsService.forTest();

      for (var i = 0; i < 3; i++) {
        ws.send({'type': 'text', 'content': '$i', 'client_ref': 'r$i'});
      }

      final contents = ws.debugOutbox
          .map((raw) => (jsonDecode(raw) as Map)['content'])
          .toList();
      expect(contents, ['0', '1', '2'],
          reason: 'messages must arrive in the order they were written');
    });

    test('ephemeral frames are dropped, not queued', () {
      final ws = WsService.forTest();

      ws.send({'type': 'ping'});
      ws.send({'type': 'typing_start', 'to': 'bob'});
      ws.send({'type': 'typing_stop', 'to': 'bob'});
      ws.send({'type': 'presence'});

      // Replaying "typing…" minutes later is noise, and a stale heartbeat
      // says nothing true.
      expect(ws.debugOutbox, isEmpty);
    });

    test('durable frames are all kept', () {
      final ws = WsService.forTest();

      for (final type in ['text', 'group_text', 'skdm', 'unsend', 'read']) {
        ws.send({'type': type, 'client_ref': type});
      }

      expect(ws.debugOutbox, hasLength(5));
    });

    test('the queue is bounded', () {
      final ws = WsService.forTest();

      for (var i = 0; i < 250; i++) {
        ws.send({'type': 'text', 'content': '$i'});
      }

      // A device offline for a long time must not grow without limit.
      expect(ws.debugOutbox.length, lessThanOrEqualTo(200));
      // The oldest are the ones dropped, so the most recent survive.
      final last = jsonDecode(ws.debugOutbox.last) as Map;
      expect(last['content'], '249');
    });
  });

  group('reconnection', () {
    test('a dropped socket schedules another attempt', () {
      final ws = WsService.forTest()..debugWantConnection = true;

      ws.debugHandleDisconnect();

      expect(ws.debugReconnectScheduled, isTrue,
          reason: 'a drop used to be the end: nothing ever reconnected');
    });

    test('backoff grows rather than hammering the server', () {
      final ws = WsService.forTest()..debugWantConnection = true;

      final delays = <Duration>[];
      for (var i = 0; i < 4; i++) {
        delays.add(ws.debugNextBackoff());
      }

      for (var i = 1; i < delays.length; i++) {
        expect(delays[i], greaterThan(delays[i - 1]),
            reason: 'each retry must wait longer than the last');
      }
    });

    test('backoff is capped', () {
      final ws = WsService.forTest()..debugWantConnection = true;

      Duration last = Duration.zero;
      for (var i = 0; i < 20; i++) {
        last = ws.debugNextBackoff();
      }

      // 30s ceiling plus up to half again in jitter.
      expect(last, lessThanOrEqualTo(const Duration(seconds: 45)));
    });

    test('signing out stops the retries', () async {
      final ws = WsService.forTest()..debugWantConnection = true;

      await ws.disconnect();
      ws.debugHandleDisconnect();

      // Otherwise it would keep trying to re-establish a session that was
      // just revoked.
      expect(ws.debugReconnectScheduled, isFalse);
    });

    test('signing out discards anything still queued', () async {
      final ws = WsService.forTest();
      ws.send({'type': 'text', 'content': 'unsent'});

      await ws.disconnect();

      // The next person on this device must not send the previous one's
      // unsent messages.
      expect(ws.debugOutbox, isEmpty);
    });
  });
}
