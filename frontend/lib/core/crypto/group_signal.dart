import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'secret_store.dart';
import 'sender_key_store.dart';
import 'signal.dart';

/// Raised when a group message cannot be read.
class GroupDecryptionFailed implements Exception {
  const GroupDecryptionFailed(this.reason);
  final String reason;

  @override
  String toString() => 'group decryption failed: $reason';
}

/// A key this device must send to one member before it can post.
class PendingDistribution {
  const PendingDistribution({
    required this.groupId,
    required this.epoch,
    required this.recipientId,
    required this.payload,
  });

  final String groupId;
  final int epoch;
  final String recipientId;

  /// The distribution message, already encrypted for [recipientId] with the
  /// pairwise session. The server routes it and cannot read it.
  final String payload;
}

/// Group encryption, using Signal's sender keys.
///
/// A group message is encrypted once with a key belonging to the sender,
/// which every member holds a copy of. The alternative — encrypting once per
/// member — costs O(members) per message and makes a fifty-person group
/// unusable.
///
/// The cost of that design is that a member who leaves can still read later
/// messages, because they still hold the key. Rotation is what closes that,
/// and here it is structural: the membership epoch is part of the sender key's
/// name, so a changed epoch is necessarily a different key. There is no code
/// path where the epoch moves and the old key keeps being used.
class GroupSignalService {
  GroupSignalService({
    required this.userId,
    required SignalService pairwise,
    SecretStore? secrets,
    PersistentSenderKeyStore? store,
  })  : _pairwise = pairwise,
        _store = store ??
            PersistentSenderKeyStore(secrets ?? SecureSecretStore());

  final String userId;

  /// The one-to-one service. Distribution messages travel over pairwise
  /// sessions, which is what stops the server substituting its own key.
  final SignalService _pairwise;

  final PersistentSenderKeyStore _store;

  static const _envelopeVersion = 1;

  PersistentSenderKeyStore get store => _store;

  SenderKeyName _nameFor(String groupId, int epoch, String senderId) =>
      GroupSenderKeys.name(
        groupId: groupId,
        epoch: epoch,
        senderId: senderId,
        deviceId: SignalService.deviceId,
      );

  // ── Distribution ──────────────────────────────────────────────────────────

  /// Builds the distribution messages this device owes [members] for the
  /// current [epoch], each encrypted for one recipient.
  ///
  /// Called before posting. A member who has not received it cannot read
  /// anything this device sends, and there is no way for them to ask.
  Future<List<PendingDistribution>> distributionsFor({
    required String groupId,
    required int epoch,
    required List<String> members,
  }) async {
    final name = _nameFor(groupId, epoch, userId);
    final builder = GroupSessionBuilder(_store);
    // Mints the key on first call for this epoch, and returns the existing
    // one afterwards, so re-distributing does not reset the chain.
    final distribution = await builder.create(name);
    final bytes = distribution.serialize();

    final out = <PendingDistribution>[];
    for (final member in members) {
      if (member == userId) continue; // we already have our own key

      try {
        final payload = await _pairwise.encrypt(
          jsonEncode({
            'v': _envelopeVersion,
            'group': groupId,
            'epoch': epoch,
            'skdm': base64Encode(bytes),
          }),
          member,
        );
        out.add(PendingDistribution(
          groupId: groupId,
          epoch: epoch,
          recipientId: member,
          payload: payload,
        ));
      } on PeerHasNoKeys {
        // They have never published keys, so they cannot receive anything
        // encrypted. Skipped rather than failing the whole distribution —
        // one member who has not opened the app must not stop the group.
        continue;
      } on IdentityChanged {
        // Their identity key changed. Sending the group key to whoever now
        // holds that identity is exactly what must not happen silently.
        rethrow;
      }
    }
    return out;
  }

  /// Handles a distribution message received from [senderId].
  ///
  /// The outer layer was pairwise encrypted, so by the time this is called
  /// the sender is authenticated by the one-to-one session.
  Future<void> acceptDistribution({
    required String senderId,
    required String decryptedPayload,
  }) async {
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(decryptedPayload) as Map<String, dynamic>;
    } catch (_) {
      throw const GroupDecryptionFailed('malformed distribution message');
    }

    if (parsed['v'] != _envelopeVersion) {
      throw GroupDecryptionFailed(
          'unsupported distribution version ${parsed['v']}');
    }

    final groupId = parsed['group'] as String?;
    final epoch = (parsed['epoch'] as num?)?.toInt();
    final skdm = parsed['skdm'] as String?;
    if (groupId == null || epoch == null || skdm == null) {
      throw const GroupDecryptionFailed('incomplete distribution message');
    }

    final name = _nameFor(groupId, epoch, senderId);
    await GroupSessionBuilder(_store).process(
      name,
      distributionFromBytes(base64Decode(skdm)),
    );
  }

  /// Whether this device holds a usable key for [senderId] at [epoch].
  Future<bool> hasSenderKey({
    required String groupId,
    required int epoch,
    required String senderId,
  }) async {
    final record = await _store.loadSenderKey(
      _nameFor(groupId, epoch, senderId),
    );
    return !record.isEmpty;
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  /// Encrypts a group message. One encryption, whatever the group's size.
  Future<String> encrypt({
    required String groupId,
    required int epoch,
    required String plaintext,
  }) async {
    final cipher = GroupCipher(_store, _nameFor(groupId, epoch, userId));
    final ciphertext = await cipher.encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    return jsonEncode({
      'v': _envelopeVersion,
      // The epoch travels with the message so the recipient knows which key
      // to try. Without it, a message sent just before a rotation would be
      // undecryptable for no discoverable reason.
      'e': epoch,
      'b': base64Encode(ciphertext),
    });
  }

  /// Decrypts a group message from [senderId].
  ///
  /// Throws [GroupDecryptionFailed] rather than returning anything readable.
  /// A group message that cannot be verified must not be displayed as though
  /// it had been.
  Future<String> decrypt({
    required String groupId,
    required String senderId,
    required String envelope,
  }) async {
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(envelope) as Map<String, dynamic>;
    } catch (_) {
      throw const GroupDecryptionFailed('not an encrypted group message');
    }

    if (parsed['v'] != _envelopeVersion) {
      throw GroupDecryptionFailed('unsupported envelope version ${parsed['v']}');
    }
    final epoch = (parsed['e'] as num?)?.toInt();
    final body = parsed['b'] as String?;
    if (epoch == null || body == null) {
      throw const GroupDecryptionFailed('incomplete group envelope');
    }

    final cipher = GroupCipher(_store, _nameFor(groupId, epoch, senderId));
    try {
      return utf8.decode(await cipher.decrypt(base64Decode(body)));
    } on DuplicateMessageException {
      rethrow;
    } catch (e) {
      // Includes the case that matters: no key for this sender at this
      // epoch, which is what a removed member sees for everything sent
      // after they were removed.
      throw GroupDecryptionFailed('$e');
    }
  }

  /// Whether this envelope is one of ours.
  static bool isEnvelope(String? content) {
    if (content == null || !content.startsWith('{')) return false;
    try {
      final parsed = jsonDecode(content);
      return parsed is Map<String, dynamic> &&
          parsed['v'] == _envelopeVersion &&
          parsed['e'] is num &&
          parsed['b'] is String;
    } catch (_) {
      return false;
    }
  }

  // ── Housekeeping ──────────────────────────────────────────────────────────

  /// Called after acting on a new epoch.
  Future<void> pruneOldEpochs(String groupId, int currentEpoch) =>
      _store.pruneOldEpochs(groupId, currentEpoch);

  /// Called on leaving a group.
  Future<void> forgetGroup(String groupId) => _store.forgetGroup(groupId);
}
