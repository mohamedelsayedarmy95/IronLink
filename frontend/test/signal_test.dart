import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/crypto/key_repository.dart';
import 'package:ironlink/core/crypto/secret_store.dart';
import 'package:ironlink/core/crypto/signal.dart';
import 'package:ironlink/core/crypto/signal_store.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// A stand-in for the key directory that behaves the way the real server does:
/// it holds only public material, and it hands out each one-time pre-key once.
///
/// This is what makes the test meaningful — Alice and Bob share nothing except
/// what actually crosses the wire, so a passing round trip proves the two
/// devices really did agree on a key without the directory knowing it.
class FakeDirectory implements KeyRepository {
  final Map<String, Map<String, dynamic>> _bundles = {};
  final Map<String, List<PreKeyRecord>> _preKeys = {};

  /// Set by the service under test before publishing.
  String? publishingAs;

  int handedOutWithoutOneTimeKey = 0;

  @override
  Future<void> publishBundle({
    required int registrationId,
    required IdentityKey identityKey,
    required SignedPreKeyRecord signedPreKey,
    required List<PreKeyRecord> oneTimePreKeys,
  }) async {
    final user = publishingAs!;
    _bundles[user] = {
      'registration_id': registrationId,
      'identity_key': base64Encode(identityKey.serialize()),
      'signed_prekey_id': signedPreKey.id,
      'signed_prekey_public':
          base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
      'signed_prekey_signature': base64Encode(signedPreKey.signature),
    };
    _preKeys[user] = [...oneTimePreKeys];
  }

  @override
  Future<void> replenishPreKeys(List<PreKeyRecord> preKeys) async {
    (_preKeys[publishingAs!] ??= []).addAll(preKeys);
  }

  @override
  Future<int> remainingPreKeys() async =>
      _preKeys[publishingAs]?.length ?? 0;

  @override
  Future<RemoteKeyBundle?> fetchBundle(String userId) async {
    final bundle = _bundles[userId];
    if (bundle == null) return null;

    final available = _preKeys[userId] ?? [];
    final json = Map<String, dynamic>.from(bundle);
    if (available.isEmpty) {
      handedOutWithoutOneTimeKey++;
    } else {
      // Claimed, exactly as the server's DELETE ... RETURNING does.
      final claimed = available.removeAt(0);
      json['one_time_prekey_id'] = claimed.id;
      json['one_time_prekey'] =
          base64Encode(claimed.getKeyPair().publicKey.serialize());
    }
    return RemoteKeyBundle.fromJson(json);
  }
}

void main() {
  late FakeDirectory directory;

  setUp(() => directory = FakeDirectory());

  Future<SignalService> device(String userId, {SecretStore? secrets}) async {
    final service = SignalService(
      userId,
      keys: directory,
      secrets: secrets ?? MemorySecretStore(),
    );
    directory.publishingAs = userId;
    await service.ensureInstalled();
    return service;
  }

  group('a real session between two devices', () {
    test('a message encrypted by one is readable only by the other', () async {
      final alice = await device('alice');
      final bob = await device('bob');

      directory.publishingAs = 'alice';
      final envelope = await alice.encrypt('the briefing is at 0600', 'bob');

      // Nothing recognisable survives on the wire.
      expect(envelope, isNot(contains('briefing')));
      expect(base64Encode(utf8.encode('the briefing is at 0600')),
          isNot(anyOf(contains(envelope), equals(envelope))));

      expect(await bob.decrypt(envelope, 'alice'), 'the briefing is at 0600');
    });

    test('the reply direction works too', () async {
      final alice = await device('alice');
      final bob = await device('bob');

      final first = await alice.encrypt('are you there', 'bob');
      expect(await bob.decrypt(first, 'alice'), 'are you there');

      // Bob now has a session from receiving, and can answer without
      // fetching a bundle of his own.
      final reply = await bob.encrypt('yes', 'alice');
      expect(await alice.decrypt(reply, 'bob'), 'yes');
    });

    test('the ratchet advances — each message has a distinct ciphertext',
        () async {
      final alice = await device('alice');
      final bob = await device('bob');

      final one = await alice.encrypt('repeat', 'bob');
      final two = await alice.encrypt('repeat', 'bob');

      // Identical plaintext must not produce identical ciphertext, or the
      // traffic leaks which messages are the same.
      expect(one, isNot(two));
      expect(await bob.decrypt(one, 'alice'), 'repeat');
      expect(await bob.decrypt(two, 'alice'), 'repeat');
    });

    test('messages arriving out of order still decrypt', () async {
      final alice = await device('alice');
      final bob = await device('bob');

      final one = await alice.encrypt('first', 'bob');
      final two = await alice.encrypt('second', 'bob');
      final three = await alice.encrypt('third', 'bob');

      // Networks reorder. The ratchet has to tolerate it or a delayed
      // message would break the conversation permanently.
      expect(await bob.decrypt(three, 'alice'), 'third');
      expect(await bob.decrypt(one, 'alice'), 'first');
      expect(await bob.decrypt(two, 'alice'), 'second');
    });

    test('replaying a message is refused', () async {
      final alice = await device('alice');
      final bob = await device('bob');

      final envelope = await alice.encrypt('transfer approved', 'bob');
      expect(await bob.decrypt(envelope, 'alice'), 'transfer approved');

      // Delivering the same ciphertext twice must not produce the message
      // twice — that is how a captured order gets executed again.
      await expectLater(
        bob.decrypt(envelope, 'alice'),
        throwsA(isA<DuplicateMessageException>()),
      );
    });

    test('a third party holding the ciphertext cannot read it', () async {
      final alice = await device('alice');
      await device('bob');
      final mallory = await device('mallory');

      final envelope = await alice.encrypt('classified', 'bob');

      // Mallory has the directory, the envelope, and a valid install —
      // everything except Bob's private keys.
      await expectLater(
        mallory.decrypt(envelope, 'alice'),
        throwsA(isA<EncryptionFailed>()),
      );
    });
  });

  group('the server is not trusted', () {
    test('a tampered signed pre-key signature is rejected', () async {
      final alice = await device('alice');
      await device('bob');

      // A malicious directory substituting its own key is exactly the attack
      // the signature check exists to stop.
      final bobBundle = await directory.fetchBundle('bob');
      final forged = Map<String, dynamic>.from({
        'registration_id': bobBundle!.registrationId,
        'identity_key': base64Encode(bobBundle.identityKey),
        'signed_prekey_id': bobBundle.signedPreKeyId,
        'signed_prekey_public': base64Encode(bobBundle.signedPreKeyPublic),
        // One flipped byte in the signature.
        'signed_prekey_signature': base64Encode(
          Uint8ListFrom(bobBundle.signedPreKeySignature)..[0] ^= 0xFF,
        ),
      });
      directory._bundles['bob'] = forged;

      await expectLater(
        alice.encrypt('should never be sent', 'bob'),
        throwsA(isA<EncryptionFailed>()),
      );
    });

    test('a peer with no published keys cannot be messaged', () async {
      final alice = await device('alice');

      await expectLater(
        alice.encrypt('hello', 'nobody'),
        throwsA(isA<PeerHasNoKeys>()),
      );
    });
  });

  group('failing closed', () {
    test('plaintext on the wire is refused, not displayed', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await bob.decrypt(await alice.encrypt('hi', 'bob'), 'alice');

      // If a downgrade ever put raw text on the wire, showing it would tell
      // the user their secret chat worked when it did not.
      await expectLater(
        bob.decrypt('just some text', 'alice'),
        throwsA(isA<EncryptionFailed>()),
      );
    });

    test('an unknown envelope version is refused', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      final envelope =
          jsonDecode(await alice.encrypt('hi', 'bob')) as Map<String, dynamic>;

      await expectLater(
        bob.decrypt(jsonEncode({...envelope, 'v': 99}), 'alice'),
        throwsA(isA<EncryptionFailed>()),
      );
    });
  });

  group('surviving a restart', () {
    test('keys and sessions persist across a new service instance', () async {
      final aliceSecrets = MemorySecretStore();
      final bobSecrets = MemorySecretStore();

      final alice = await device('alice', secrets: aliceSecrets);
      final bob = await device('bob', secrets: bobSecrets);
      await bob.decrypt(await alice.encrypt('before', 'bob'), 'alice');

      // Same storage, new objects — this is what an app restart looks like.
      directory.publishingAs = 'alice';
      final aliceAgain =
          SignalService('alice', keys: directory, secrets: aliceSecrets);
      await aliceAgain.ensureInstalled();
      directory.publishingAs = 'bob';
      final bobAgain =
          SignalService('bob', keys: directory, secrets: bobSecrets);
      await bobAgain.ensureInstalled();

      expect(await aliceAgain.hasSession('bob'), isTrue,
          reason: 'a lost session means no past message can be read again');

      final envelope = await aliceAgain.encrypt('after', 'bob');
      expect(await bobAgain.decrypt(envelope, 'alice'), 'after');
    });

    test('reinstalling does not regenerate the identity key', () async {
      final secrets = MemorySecretStore();
      final first = await device('alice', secrets: secrets);
      final firstKey =
          (await first.store.getIdentityKeyPair()).getPublicKey();

      directory.publishingAs = 'alice';
      final second = SignalService('alice', keys: directory, secrets: secrets);
      await second.ensureInstalled();

      // A regenerated identity would silently break every existing session.
      expect((await second.store.getIdentityKeyPair()).getPublicKey(),
          firstKey);
    });

    test('sign-out erases the key material', () async {
      final secrets = MemorySecretStore();
      final alice = await device('alice', secrets: secrets);

      await alice.reset();

      // Anything left behind lets the next person on a shared device read
      // cached traffic.
      expect(await secrets.keys(), isEmpty);
    });
  });

  group('identity change', () {
    test('a peer whose identity key changed is refused until confirmed',
        () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await bob.decrypt(await alice.encrypt('hello', 'bob'), 'alice');

      // Bob reinstalls: same user id, brand new keys. Indistinguishable
      // from someone impersonating him, so it must not pass silently.
      final bobReinstalled = await device('bob');
      final address = SignalProtocolAddress('bob', SignalService.deviceId);

      final newIdentity =
          (await bobReinstalled.store.getIdentityKeyPair()).getPublicKey();
      final trusted = await alice.store.getIdentity(address);
      expect(trusted, isNot(newIdentity));

      expect(
        await alice.store.isTrustedIdentity(
            address, newIdentity, Direction.receiving),
        isFalse,
      );

      // After the user confirms, the old session is dropped and a new one
      // opens cleanly.
      await alice.acceptIdentityChange('bob', newIdentity);
      expect(await alice.hasSession('bob'), isFalse);

      final envelope = await alice.encrypt('still there?', 'bob');
      expect(await bobReinstalled.decrypt(envelope, 'alice'), 'still there?');
    });
  });

  group('pre-keys', () {
    test('a bundle without a one-time pre-key still opens a session',
        () async {
      final alice = await device('alice');
      final bob = await device('bob');

      // Drain Bob's pre-keys, which happens when he has been offline while
      // many people started conversations with him.
      directory._preKeys['bob']!.clear();

      final envelope = await alice.encrypt('urgent', 'bob');
      expect(directory.handedOutWithoutOneTimeKey, 1);
      // Refusing to send here would be worse than the slightly weaker
      // forward secrecy of this first message.
      expect(await bob.decrypt(envelope, 'alice'), 'urgent');
    });

    test('each sender claims a different one-time pre-key', () async {
      await device('bob');

      final first = await directory.fetchBundle('bob');
      final second = await directory.fetchBundle('bob');

      // Two senders given the same pre-key would derive related session
      // keys — the reason the server claims atomically.
      expect(first!.oneTimePreKeyId, isNot(second!.oneTimePreKeyId));
    });
  });
}

/// Small helper so the tamper test can mutate a copy rather than the original.
// ignore: non_constant_identifier_names
List<int> Uint8ListFrom(List<int> source) => List<int>.from(source);
