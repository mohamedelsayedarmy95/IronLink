import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/client_ref.dart';

/// The references the client puts on messages are its idempotency keys.
///
/// The server keys deduplication on `(sender_id, client_ref)`, so two logical
/// messages that share a reference do not merely look alike — the second one
/// is returned as the first, never stored, and never delivered. A per-screen
/// counter produced `ref_1` on every newly opened chat.
void main() {
  test('references are random, prefixed, and fit the stored column', () {
    final refs = {for (var i = 0; i < 1000; i++) newClientRef('ref')};

    expect(refs, hasLength(1000),
        reason: 'a collision here is a message the server will drop');
    for (final ref in refs) {
      expect(ref, matches(RegExp(r'^ref_[0-9a-f]{32}$')));
      expect(ref.length, lessThanOrEqualTo(64),
          reason: 'Message.client_ref is String(64)');
    }
  });

  test('every producer prefix stays inside the database limit', () {
    for (final prefix in ['ref', 'rx', 'skdm']) {
      final ref = newClientRef(prefix);
      expect(ref, startsWith('${prefix}_'),
          reason: 'ack handlers filter on the existing prefixes');
      expect(ref.length, lessThanOrEqualTo(64));
    }
  });

  test('two fresh callers cannot start from the same value', () {
    // The old counter produced `ref_1` for the first message of every ChatBloc
    // and every app launch.
    expect(newClientRef('ref'), isNot(newClientRef('ref')));
  });
}
