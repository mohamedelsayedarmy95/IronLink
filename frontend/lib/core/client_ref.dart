import 'dart:math';

/// Generates the client idempotency key for one logical message.
///
/// The server deduplicates on `(sender_id, client_ref)`. A reference that
/// repeats for the same sender therefore does not merely look odd — the server
/// treats the new message as a retransmission of the old one and returns the
/// stored row instead of writing the new message. The previous generator was a
/// per-bloc counter that started at zero, so every conversation a person
/// opened produced `ref_1`, and the first message in a later chat could be
/// swallowed by the first one.
///
/// Sixteen secure-random bytes, hex encoded: 32 characters plus the prefix,
/// well inside the 64-character column. Random rather than sequential because
/// there is no counter to reset, no screen lifetime to outlive, and no shared
/// state two blocs could race on.
///
/// A retransmission does not call this again. The encoded frame, reference
/// included, is stored in the outbox and replayed byte for byte, so the same
/// logical message keeps the same reference.
String newClientRef(String prefix) {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final buffer = StringBuffer()
    ..write(prefix)
    ..write('_');
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
