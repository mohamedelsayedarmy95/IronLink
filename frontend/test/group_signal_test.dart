import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/crypto/attachment_crypto.dart';
import 'package:ironlink/core/crypto/group_signal.dart';
import 'package:ironlink/core/crypto/secret_store.dart';
import 'package:ironlink/core/crypto/sender_key_store.dart';
import 'package:ironlink/core/crypto/signal.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'signal_test_support.dart';

/// Group encryption via sender keys.
///
/// The property these exist for is the one groups get wrong: removing someone
/// from the member list does not remove their access, because they still hold
/// the sender key. Only rotation ends it. Everything here is arranged so that
/// claim can be checked rather than asserted.
void main() {
  late FakeDirectory directory;

  setUp(() => directory = FakeDirectory());

  /// One member's device: a pairwise service plus a group service sharing
  /// its storage, exactly as the app wires them.
  Future<({SignalService pairwise, GroupSignalService group})> device(
    String userId, {
    SecretStore? secrets,
  }) async {
    final store = secrets ?? MemorySecretStore();
    final pairwise = SignalService(userId, keys: directory, secrets: store);
    directory.publishingAs = userId;
    await pairwise.ensureInstalled();
    return (
      pairwise: pairwise,
      group: GroupSignalService(
        userId: userId,
        pairwise: pairwise,
        secrets: store,
      ),
    );
  }

  /// Hands [from]'s distribution messages to the members that should get
  /// them, decrypting the pairwise layer the way the app does on receipt.
  Future<void> distribute({
    required ({SignalService pairwise, GroupSignalService group}) from,
    required String fromId,
    required String groupId,
    required int epoch,
    required Map<String, ({SignalService pairwise, GroupSignalService group})>
        recipients,
  }) async {
    final pending = await from.group.distributionsFor(
      groupId: groupId,
      epoch: epoch,
      members: [fromId, ...recipients.keys],
    );

    for (final d in pending) {
      final target = recipients[d.recipientId]!;
      final payload = await target.pairwise.decrypt(d.payload, fromId);
      await target.group.acceptDistribution(
        senderId: fromId,
        decryptedPayload: payload,
      );
    }
  }

  group('a group conversation', () {
    test('every member reads a message the sender encrypted once', () async {
      const groupId = 'g1';
      final alice = await device('alice');
      final bob = await device('bob');
      final carol = await device('carol');

      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: groupId,
        epoch: 1,
        recipients: {'bob': bob, 'carol': carol},
      );

      final envelope = await alice.group.encrypt(
        groupId: groupId,
        epoch: 1,
        plaintext: 'move at 0600',
      );

      // One ciphertext, read by everyone — not one encryption per member.
      expect(
        await bob.group
            .decrypt(groupId: groupId, senderId: 'alice', envelope: envelope),
        'move at 0600',
      );
      expect(
        await carol.group
            .decrypt(groupId: groupId, senderId: 'alice', envelope: envelope),
        'move at 0600',
      );
    });

    test('nothing readable is on the wire', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );

      final envelope = await alice.group
          .encrypt(groupId: 'g1', epoch: 1, plaintext: 'classified');
      expect(envelope, isNot(contains('classified')));
    });

    test('a member who never received the key cannot read', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      final mallory = await device('mallory');

      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );

      final envelope =
          await alice.group.encrypt(groupId: 'g1', epoch: 1, plaintext: 'x');

      await expectLater(
        mallory.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: envelope),
        throwsA(isA<GroupDecryptionFailed>()),
      );
    });

    test('each member can send, not just the one who started', () async {
      final alice = await device('alice');
      final bob = await device('bob');

      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );
      await distribute(
        from: bob,
        fromId: 'bob',
        groupId: 'g1',
        epoch: 1,
        recipients: {'alice': alice},
      );

      final fromBob =
          await bob.group.encrypt(groupId: 'g1', epoch: 1, plaintext: 'ack');
      expect(
        await alice.group
            .decrypt(groupId: 'g1', senderId: 'bob', envelope: fromBob),
        'ack',
      );
    });

    test('messages arriving out of order still decrypt', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );

      final one =
          await alice.group.encrypt(groupId: 'g1', epoch: 1, plaintext: '1');
      final two =
          await alice.group.encrypt(groupId: 'g1', epoch: 1, plaintext: '2');

      expect(
        await bob.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: two),
        '2',
      );
      expect(
        await bob.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: one),
        '1',
      );
    });
  });

  group('attachments and voice notes', () {
    // A group attachment is encrypted ONCE with its own AES-GCM key, and
    // that key rides the group envelope — so the cost is one attachment
    // encryption for the whole group, not one per member.

    test('the key that opens an attachment reaches every member', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      final carol = await device('carol');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob, 'carol': carol},
      );

      final crypto = AttachmentCrypto();
      final plaintext =
          Uint8List.fromList(utf8.encode('the contents of a briefing'));
      final key = crypto.newKey(mimeType: 'image/jpeg', sizeBytes: 11);
      final stored = crypto.encrypt(plaintext, key);

      final envelope = await alice.group.encrypt(
        groupId: 'g1',
        epoch: 1,
        plaintext: jsonEncode({
          'media_key': 'obj-1',
          'caption': 'map',
          'mime': 'image/jpeg',
          'att': key.toJson(),
        }),
      );

      for (final member in [bob, carol]) {
        final payload = jsonDecode(await member.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: envelope));
        final recovered = AttachmentKey.fromJson(
            (payload as Map<String, dynamic>)['att'] as Map<String, dynamic>);

        expect(payload['media_key'], 'obj-1');
        expect(crypto.decrypt(stored, recovered), plaintext);
      }
    });

    test('a removed member cannot open an attachment sent afterwards',
        () async {
      final alice = await device('alice');
      final bob = await device('bob');
      final carol = await device('carol');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob, 'carol': carol},
      );

      // Bob is removed; epoch 2 goes to Carol only.
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 2,
        recipients: {'carol': carol},
      );

      final key = AttachmentCrypto()
          .newKey(mimeType: 'application/pdf', sizeBytes: 4);
      final envelope = await alice.group.encrypt(
        groupId: 'g1',
        epoch: 2,
        plaintext: jsonEncode({'media_key': 'obj-2', 'att': key.toJson()}),
      );

      // The stored object is reachable by anyone who knows its key — but the
      // key to open it is inside an envelope Bob can no longer read.
      await expectLater(
        bob.group.decrypt(groupId: 'g1', senderId: 'alice', envelope: envelope),
        throwsA(isA<GroupDecryptionFailed>()),
      );
      expect(
        await carol.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: envelope),
        contains('obj-2'),
      );
    });

    test('voice metadata travels inside the envelope, not beside it',
        () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );

      final key = AttachmentCrypto()
          .newKey(mimeType: 'audio/mp4', sizeBytes: 2048);
      final envelope = await alice.group.encrypt(
        groupId: 'g1',
        epoch: 1,
        plaintext: jsonEncode({
          'media_key': 'obj-3',
          'mime': 'audio/mp4',
          'att': key.toJson(),
          'dur': 12.5,
          'wave': [0.1, 0.8, 0.3],
        }),
      );

      // How long a message is, and its shape, are things the server should
      // not learn — so they are not wire fields.
      expect(envelope, isNot(contains('12.5')));
      expect(envelope, isNot(contains('obj-3')));

      final payload = jsonDecode(await bob.group
          .decrypt(groupId: 'g1', senderId: 'alice', envelope: envelope));
      expect(payload['dur'], 12.5);
      expect(payload['wave'], [0.1, 0.8, 0.3]);
      expect(payload['media_key'], 'obj-3');
    });
  });

  group('removing a member', () {
    test('THE PROPERTY: a removed member cannot read what follows', () async {
      const groupId = 'ops';
      final alice = await device('alice');
      final bob = await device('bob');
      final carol = await device('carol');

      // Epoch 1: all three in the group.
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: groupId,
        epoch: 1,
        recipients: {'bob': bob, 'carol': carol},
      );
      final before = await alice.group
          .encrypt(groupId: groupId, epoch: 1, plaintext: 'before removal');
      expect(
        await bob.group.decrypt(
            groupId: groupId, senderId: 'alice', envelope: before),
        'before removal',
      );

      // Bob is removed. The server bumps the epoch to 2; Alice re-distributes
      // to the remaining members only.
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: groupId,
        epoch: 2,
        recipients: {'carol': carol},
      );

      final after = await alice.group
          .encrypt(groupId: groupId, epoch: 2, plaintext: 'after removal');

      // Carol still reads.
      expect(
        await carol.group
            .decrypt(groupId: groupId, senderId: 'alice', envelope: after),
        'after removal',
      );

      // Bob does not. This is the whole point of the epoch: without the
      // rotation he would decrypt this with the key he already had.
      await expectLater(
        bob.group
            .decrypt(groupId: groupId, senderId: 'alice', envelope: after),
        throwsA(isA<GroupDecryptionFailed>()),
      );
    });

    test('a removed member can still read what was sent before — and that is '
        'the honest limit of this design', () async {
      final alice = await device('alice');
      final bob = await device('bob');

      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );
      final old = await alice.group
          .encrypt(groupId: 'g1', epoch: 1, plaintext: 'old news');

      // Bob is removed at epoch 2, but he had this message already. Nothing
      // can retract it, and pretending otherwise would be a false claim.
      expect(
        await bob.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: old),
        'old news',
      );
    });

    test('a rotation the sender ignores is impossible to express', () async {
      // The epoch is part of the sender key's NAME, so encrypting at a new
      // epoch cannot reuse the old key even by mistake.
      final alice = await device('alice');

      final one = GroupSenderKeys.name(
          groupId: 'g1', epoch: 1, senderId: 'alice');
      final two = GroupSenderKeys.name(
          groupId: 'g1', epoch: 2, senderId: 'alice');

      expect(one, isNot(two));
      expect(one.serialize(), isNot(two.serialize()));
    });
  });

  group('adding a member', () {
    test('a new member reads messages sent after they joined', () async {
      final alice = await device('alice');
      final bob = await device('bob');

      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );

      // Carol joins; the epoch becomes 2 and Alice distributes to both.
      final carol = await device('carol');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 2,
        recipients: {'bob': bob, 'carol': carol},
      );

      final envelope = await alice.group
          .encrypt(groupId: 'g1', epoch: 2, plaintext: 'welcome');
      expect(
        await carol.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: envelope),
        'welcome',
      );
      expect(
        await bob.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: envelope),
        'welcome',
      );
    });

    test('a new member cannot read what was sent before they arrived',
        () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );
      final earlier =
          await alice.group.encrypt(groupId: 'g1', epoch: 1, plaintext: 'past');

      final carol = await device('carol');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 2,
        recipients: {'bob': bob, 'carol': carol},
      );

      // The group's past is not handed over on joining, which is why the
      // server also refuses to serve history from before joined_at.
      await expectLater(
        carol.group
            .decrypt(groupId: 'g1', senderId: 'alice', envelope: earlier),
        throwsA(isA<GroupDecryptionFailed>()),
      );
    });

    test('a member with no published keys is skipped, not fatal', () async {
      final alice = await device('alice');
      final bob = await device('bob');

      // 'ghost' never opened the app, so has no key bundle.
      final pending = await alice.group.distributionsFor(
        groupId: 'g1',
        epoch: 1,
        members: ['alice', 'bob', 'ghost'],
      );

      // One absent member must not stop the group from working.
      expect(pending.map((p) => p.recipientId), ['bob']);
      expect(bob, isNotNull);
    });
  });

  group('failing closed', () {
    test('plaintext is refused, not displayed', () async {
      final bob = await device('bob');
      await expectLater(
        bob.group.decrypt(
            groupId: 'g1', senderId: 'alice', envelope: 'just some text'),
        throwsA(isA<GroupDecryptionFailed>()),
      );
    });

    test('an unknown envelope version is refused', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );
      final envelope = jsonDecode(await alice.group
          .encrypt(groupId: 'g1', epoch: 1, plaintext: 'x')) as Map;

      await expectLater(
        bob.group.decrypt(
          groupId: 'g1',
          senderId: 'alice',
          envelope: jsonEncode({...envelope, 'v': 99}),
        ),
        throwsA(isA<GroupDecryptionFailed>()),
      );
    });

    test('a malformed distribution message is refused', () async {
      final bob = await device('bob');
      await expectLater(
        bob.group.acceptDistribution(
            senderId: 'alice', decryptedPayload: 'not json'),
        throwsA(isA<GroupDecryptionFailed>()),
      );
    });

    test('recognising our own envelopes is strict', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );

      expect(
        GroupSignalService.isEnvelope(
          await alice.group.encrypt(groupId: 'g1', epoch: 1, plaintext: 'x'),
        ),
        isTrue,
      );
      for (final text in ['hello', '{"v":1}', '{"e":1,"b":"AA=="}', '']) {
        expect(GroupSignalService.isEnvelope(text), isFalse, reason: text);
      }
      expect(GroupSignalService.isEnvelope(null), isFalse);
    });
  });

  group('storage', () {
    test('keys survive a restart', () async {
      final aliceSecrets = MemorySecretStore();
      final bobSecrets = MemorySecretStore();

      final alice = await device('alice', secrets: aliceSecrets);
      final bob = await device('bob', secrets: bobSecrets);
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );

      // New objects over the same storage — an app restart.
      directory.publishingAs = 'bob';
      final bobPairwise =
          SignalService('bob', keys: directory, secrets: bobSecrets);
      await bobPairwise.ensureInstalled();
      final bobAgain = GroupSignalService(
        userId: 'bob',
        pairwise: bobPairwise,
        secrets: bobSecrets,
      );

      final envelope =
          await alice.group.encrypt(groupId: 'g1', epoch: 1, plaintext: 'kept');
      // A lost sender key means the device can read nothing until every
      // member re-distributes, and nothing would prompt them to.
      expect(
        await bobAgain.decrypt(
            groupId: 'g1', senderId: 'alice', envelope: envelope),
        'kept',
      );
    });

    test('old epochs are pruned but the previous one is kept', () async {
      final secrets = MemorySecretStore();
      final alice = await device('alice', secrets: secrets);
      final bob = await device('bob');

      for (final epoch in [1, 2, 3]) {
        await distribute(
          from: alice,
          fromId: 'alice',
          groupId: 'g1',
          epoch: epoch,
          recipients: {'bob': bob},
        );
      }

      await alice.group.pruneOldEpochs('g1', 3);

      // Epoch 2 is kept so a message in flight across the rotation still
      // opens; epoch 1 is gone.
      expect(
        await alice.group
            .hasSenderKey(groupId: 'g1', epoch: 3, senderId: 'alice'),
        isTrue,
      );
      expect(
        await alice.group
            .hasSenderKey(groupId: 'g1', epoch: 2, senderId: 'alice'),
        isTrue,
      );
      expect(
        await alice.group
            .hasSenderKey(groupId: 'g1', epoch: 1, senderId: 'alice'),
        isFalse,
      );
    });

    test('leaving a group forgets its keys', () async {
      final secrets = MemorySecretStore();
      final alice = await device('alice', secrets: secrets);
      final bob = await device('bob');

      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'other',
        epoch: 1,
        recipients: {'bob': bob},
      );

      await alice.group.forgetGroup('g1');

      expect(
        await alice.group
            .hasSenderKey(groupId: 'g1', epoch: 1, senderId: 'alice'),
        isFalse,
      );
      // Only that group.
      expect(
        await alice.group
            .hasSenderKey(groupId: 'other', epoch: 1, senderId: 'alice'),
        isTrue,
      );
    });

    test('a group id containing the separator still parses', () async {
      // The scope is "groupId@epoch" and is split on the LAST separator, so
      // an id with one in it must not be mis-parsed into the wrong group.
      final parsed = GroupSenderKeys.parseScope(
        GroupSenderKeys.name(groupId: 'a@b', epoch: 7, senderId: 'x')
            .serialize(),
      );
      expect(parsed?.groupId, 'a@b');
      expect(parsed?.epoch, 7);
    });
  });

  group('the pairwise layer protects distribution', () {
    test('a distribution message is encrypted for exactly one member',
        () async {
      final alice = await device('alice');
      final bob = await device('bob');
      final carol = await device('carol');

      final pending = await alice.group.distributionsFor(
        groupId: 'g1',
        epoch: 1,
        members: ['alice', 'bob', 'carol'],
      );

      expect(pending, hasLength(2));
      // Different ciphertexts: each is sealed to one recipient's session, so
      // the server cannot take one and hand it to somebody else.
      expect(pending[0].payload, isNot(pending[1].payload));

      final forBob = pending.firstWhere((p) => p.recipientId == 'bob');
      await expectLater(
        carol.pairwise.decrypt(forBob.payload, 'alice'),
        throwsA(isA<EncryptionFailed>()),
      );
      expect(await bob.pairwise.decrypt(forBob.payload, 'alice'), isNotEmpty);
    });

    test('a reinstalled member is locked out until the session is rebuilt, '
        'and is never silently handed the key', () async {
      final alice = await device('alice');
      final bob = await device('bob');
      await distribute(
        from: alice,
        fromId: 'alice',
        groupId: 'g1',
        epoch: 1,
        recipients: {'bob': bob},
      );

      // Bob reinstalls: same user id, entirely new keys.
      final bobReinstalled = await device('bob');

      // Alice has a live session with the OLD Bob and does not re-fetch his
      // bundle to send, so she cannot yet know. She encrypts to the session
      // she has — which is the safe direction: the new Bob is not handed the
      // group key, he simply cannot read it.
      final pending = await alice.group.distributionsFor(
        groupId: 'g1',
        epoch: 2,
        members: ['alice', 'bob'],
      );
      expect(pending, hasLength(1));

      await expectLater(
        bobReinstalled.pairwise.decrypt(pending.single.payload, 'alice'),
        throwsA(isA<EncryptionFailed>()),
      );

      // Alice finds out when the new Bob first reaches her, and that is
      // refused rather than accepted quietly.
      final hello = await bobReinstalled.pairwise.encrypt('it is me', 'alice');
      await expectLater(
        alice.pairwise.decrypt(hello, 'bob'),
        throwsA(isA<IdentityChanged>()),
      );
    });
  });
}
