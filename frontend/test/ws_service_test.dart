import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/outbox_store.dart';
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
///
/// The queue is a table now rather than a list. That is why every read of it
/// here is awaited, and it is the whole subject of the last two groups.
void main() {
  group('what happens to a message sent while disconnected', () {
    test('it is kept rather than dropped', () async {
      final ws = WsService.forTest();

      ws.send({'type': 'text', 'to': 'bob', 'content': 'x', 'client_ref': 'r1'});

      expect(await ws.debugOutbox, hasLength(1),
          reason: 'a message written offline must survive to be sent');
    });

    test('order is preserved', () async {
      final ws = WsService.forTest();

      for (var i = 0; i < 3; i++) {
        ws.send({'type': 'text', 'content': '$i', 'client_ref': 'r$i'});
      }

      // Three sends in the same tick. The store writes are chained rather than
      // racing precisely so this holds.
      final contents = (await ws.debugOutbox)
          .map((raw) => (jsonDecode(raw) as Map)['content'])
          .toList();
      expect(contents, ['0', '1', '2'],
          reason: 'messages must arrive in the order they were written');
    });

    test('ephemeral frames are dropped, not queued', () async {
      final ws = WsService.forTest();

      ws.send({'type': 'ping'});
      ws.send({'type': 'typing_start', 'to': 'bob'});
      ws.send({'type': 'typing_stop', 'to': 'bob'});
      ws.send({'type': 'presence'});

      // Replaying "typing…" minutes later is noise, and a stale heartbeat
      // says nothing true.
      expect(await ws.debugOutbox, isEmpty);
    });

    test('durable frames are all kept', () async {
      final ws = WsService.forTest();

      for (final type in ['text', 'group_text', 'skdm', 'unsend', 'read']) {
        ws.send({'type': type, 'client_ref': type});
      }

      expect(await ws.debugOutbox, hasLength(5));
    });

    test('the queue is bounded, and says what it dropped', () async {
      final ws = WsService.forTest();
      final announced = <String>[];
      ws.dropped.listen(announced.add);

      for (var i = 0; i < 250; i++) {
        ws.send({'type': 'text', 'content': '$i', 'client_ref': 'r$i'});
      }
      await ws.debugSettled;
      await Future<void>.delayed(Duration.zero);

      // A device offline for a long time must not grow without limit.
      final queued = await ws.debugOutbox;
      expect(queued.length, lessThanOrEqualTo(200));
      // The oldest go first, so the most recent survive.
      expect(jsonDecode(queued.last)['content'], '249');

      // And the drop is announced. It used to be silent, which left the
      // message sitting in the conversation still looking sent — the worst
      // available handling, because the sender has no way to detect it.
      expect(announced, isNotEmpty);
      expect(announced.first, 'r0', reason: 'oldest first');
    });
  });

  group('what it takes to leave the queue', () {
    test('a written frame stays until it is acknowledged', () async {
      // The change that makes this an outbox rather than a buffer. Handing
      // bytes to a sink is not delivery: a socket that dies between the write
      // and the server's processing loses the frame with no error on either
      // side, which is the case an outbox exists for.
      final ws = WsService.forTest();

      ws.send({'type': 'text', 'content': 'x', 'client_ref': 'r1'});
      await ws.debugSettled;

      expect(await ws.debugOutbox, hasLength(1));
    });

    test('an acknowledgement removes it', () async {
      final ws = WsService.forTest();
      ws.send({'type': 'text', 'content': 'x', 'client_ref': 'r1'});
      await ws.debugSettled;

      ws.debugSettle({'type': 'ack', 'client_ref': 'r1'});
      await ws.debugSettled;

      expect(await ws.debugOutbox, isEmpty);
    });

    test('a refusal removes it too, and is reported', () async {
      // Some frames the server refuses permanently — a message to someone who
      // has blocked the sender. Waiting for an acknowledgement that is never
      // coming means re-sending on every reconnect until the retries run out,
      // then failing minutes later for no reason the user can see.
      final ws = WsService.forTest();
      final announced = <String>[];
      ws.dropped.listen(announced.add);

      ws.send({'type': 'text', 'content': 'x', 'client_ref': 'r1'});
      await ws.debugSettled;

      ws.debugSettle({
        'type': 'error',
        'client_ref': 'r1',
        'detail': 'This message could not be delivered.',
      });
      await ws.debugSettled;
      await Future<void>.delayed(Duration.zero);

      expect(await ws.debugOutbox, isEmpty);
      expect(announced, ['r1']);
    });

    test('an unrelated acknowledgement removes nothing', () async {
      final ws = WsService.forTest();
      ws.send({'type': 'text', 'content': 'x', 'client_ref': 'r1'});
      await ws.debugSettled;

      ws.debugSettle({'type': 'ack', 'client_ref': 'someone-elses'});
      await ws.debugSettled;

      expect(await ws.debugOutbox, hasLength(1));
    });

    test('an error carrying no reference settles nothing', () async {
      // The server sends a few of these — malformed JSON, where there is no
      // reference to report against. Clearing on one would discard unrelated
      // messages that were perfectly good.
      final ws = WsService.forTest();
      ws.send({'type': 'text', 'content': 'x', 'client_ref': 'r1'});
      await ws.debugSettled;

      ws.debugSettle({'type': 'error', 'detail': 'invalid JSON frame'});
      await ws.debugSettled;

      expect(await ws.debugOutbox, hasLength(1));
    });
  });

  group('durability', () {
    test('the queue survives a restart', () async {
      // The whole point of the change. The optimistic bubble is written to
      // sqflite; the queued frame used to be a Dart list, so killing the app
      // left the user looking at a message in their own history that had
      // never been sent and never would be. Both sides believed it worked.
      final store = InMemoryOutboxStore();

      final before = WsService.forTest(outbox: store);
      before.send({'type': 'text', 'content': 'survive me', 'client_ref': 'r1'});
      await before.debugSettled;

      // A new service over the same storage is what a relaunch looks like.
      final after = WsService.forTest(outbox: store);

      final queued = await after.debugOutbox;
      expect(queued, hasLength(1));
      expect(jsonDecode(queued.single)['content'], 'survive me');
    });

    test('but not a sign-out', () async {
      final store = InMemoryOutboxStore();
      final ws = WsService.forTest(outbox: store);
      ws.send({'type': 'text', 'content': 'unsent', 'client_ref': 'r1'});
      await ws.debugSettled;

      await ws.disconnect();

      // The next person on this device must not send the previous one's
      // unsent messages.
      expect(await WsService.forTest(outbox: store).debugOutbox, isEmpty);
    });
  });

  group('reconnection', () {
    test('a dropped socket schedules another attempt', () {
      final ws = WsService.forTest()..debugWantConnection = true;

      ws.debugHandleDisconnect();

      expect(ws.debugReconnectScheduled, isTrue,
          reason: 'a drop used to be the end: nothing ever reconnected');
    });

    test('a drop does not discard the queue', () async {
      // Only sign-out clears it. A dropped socket is the situation the queue
      // exists for, so emptying it there would defeat the whole mechanism.
      final ws = WsService.forTest()..debugWantConnection = true;
      ws.send({'type': 'text', 'content': 'x', 'client_ref': 'r1'});
      await ws.debugSettled;

      ws.debugHandleDisconnect();

      expect(await ws.debugOutbox, hasLength(1));
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
  });
}
