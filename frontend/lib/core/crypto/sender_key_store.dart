import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'secret_store.dart';

/// Persistent [SenderKeyStore] for group messaging.
///
/// The library's in-memory store loses every sender key when the process
/// dies, which for groups means the device can decrypt nothing until every
/// member happens to re-distribute — and nothing prompts them to.
class PersistentSenderKeyStore implements SenderKeyStore {
  PersistentSenderKeyStore(this._secrets);

  final SecretStore _secrets;

  static const prefix = 'sig.sk.';

  String _key(SenderKeyName name) =>
      '$prefix${base64Url.encode(utf8.encode(name.serialize()))}';

  @override
  Future<SenderKeyRecord> loadSenderKey(SenderKeyName senderKeyName) async {
    final raw = await _secrets.read(_key(senderKeyName));
    // An empty record rather than an error: this is how the library asks
    // "do we have a key for this sender", and empty means no.
    return raw == null
        ? SenderKeyRecord()
        : SenderKeyRecord.fromSerialized(base64Decode(raw));
  }

  @override
  Future<void> storeSenderKey(
      SenderKeyName senderKeyName, SenderKeyRecord record) async {
    await _secrets.write(
      _key(senderKeyName),
      base64Encode(record.serialize()),
    );
  }

  /// Forgets sender keys for [groupId] outside the retained epoch window.
  ///
  /// Keys for older epochs decrypt only messages that were already sent, so
  /// keeping them is not a security hole — the point of rotation is that new
  /// messages use a new key. They are pruned to bound storage, keeping the
  /// previous epoch so a message that was in flight across a membership
  /// change still opens.
  Future<int> pruneOldEpochs(String groupId, int currentEpoch) async {
    var removed = 0;
    for (final key in await _secrets.keys()) {
      if (!key.startsWith(prefix)) continue;

      final name = _decodeName(key);
      if (name == null) continue;

      final parsed = GroupSenderKeys.parseScope(name);
      if (parsed == null || parsed.groupId != groupId) continue;
      if (parsed.epoch >= currentEpoch - 1) continue;

      await _secrets.delete(key);
      removed++;
    }
    return removed;
  }

  /// Drops every sender key for a group. Used on leaving one: keeping the
  /// keys would leave the device able to read anything it still receives.
  Future<void> forgetGroup(String groupId) async {
    for (final key in await _secrets.keys()) {
      if (!key.startsWith(prefix)) continue;
      final name = _decodeName(key);
      if (name == null) continue;
      final parsed = GroupSenderKeys.parseScope(name);
      if (parsed?.groupId == groupId) await _secrets.delete(key);
    }
  }

  String? _decodeName(String storageKey) {
    try {
      return utf8.decode(base64Url.decode(storageKey.substring(prefix.length)));
    } catch (_) {
      return null;
    }
  }
}

/// How a sender key is named, and why the epoch is part of the name.
///
/// [SenderKeyName] is (scope, sender). Putting the membership epoch in the
/// scope makes rotation structural rather than something the code has to
/// remember to do: a new epoch is a different name, so it necessarily has a
/// different key. There is no path where a membership change is acknowledged
/// and the old key is still used.
class GroupSenderKeys {
  const GroupSenderKeys._();

  static const _separator = '@';

  static String scope(String groupId, int epoch) =>
      '$groupId$_separator$epoch';

  static ({String groupId, int epoch})? parseScope(String serializedName) {
    // SenderKeyName.serialize() is "scope::sender::deviceId".
    final scopePart = serializedName.split('::').first;
    final at = scopePart.lastIndexOf(_separator);
    if (at <= 0) return null;
    final epoch = int.tryParse(scopePart.substring(at + 1));
    if (epoch == null) return null;
    return (groupId: scopePart.substring(0, at), epoch: epoch);
  }

  static SenderKeyName name({
    required String groupId,
    required int epoch,
    required String senderId,
    int deviceId = 1,
  }) =>
      SenderKeyName(
        scope(groupId, epoch),
        SignalProtocolAddress(senderId, deviceId),
      );
}

/// Convenience for turning stored bytes back into a distribution message.
SenderKeyDistributionMessageWrapper distributionFromBytes(Uint8List bytes) =>
    SenderKeyDistributionMessageWrapper.fromSerialized(bytes);
