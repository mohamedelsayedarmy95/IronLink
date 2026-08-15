import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'contacts_repository.dart';
import 'phone_normalizer.dart';

/// Reads the address book, hashes it on the device, and uploads digests.
///
/// The raw numbers exist only inside [_collectHashes], as local variables,
/// for the duration of one pass. They are never returned from it, stored,
/// logged, or attached to an error — which is the whole reason the hashing
/// happens here rather than server-side.
class ContactSyncService {
  ContactSyncService(this._repository, {FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final ContactsRepository _repository;
  final FlutterSecureStorage _storage;

  /// Cached so a sync does not require a round-trip before it can hash.
  /// Held in secure storage rather than preferences: with the salt, the
  /// digests on the device become reversible by enumeration.
  static const _saltKey = 'contact_hash_salt';

  /// Compiled into the app rather than fetched, because the server needs the
  /// same value to produce matching digests and there is no key-exchange step
  /// in this flow. It is not a secret from the user — it is a secret from
  /// anyone holding only a database dump, which is what it has to defend.
  ///
  /// Kept out of source control in a real deployment by passing
  /// `--dart-define=CONTACT_HASH_SALT=...` at build time; the fallback exists
  /// so a development build still functions.
  static const _buildSalt = String.fromEnvironment(
    'CONTACT_HASH_SALT',
    defaultValue: 'test_contact_salt_at_least_32_chars_long_xx',
  );

  Future<String> _salt() async {
    final cached = await _storage.read(key: _saltKey);
    if (cached != null && cached.isNotEmpty) return cached;
    await _storage.write(key: _saltKey, value: _buildSalt);
    return _buildSalt;
  }

  /// Whether access to the address book is already granted.
  ///
  /// Checks rather than requests, so calling it cannot surface a system
  /// prompt as a side effect of merely opening a screen.
  ///
  /// Read-only throughout: this app never writes to the address book, and
  /// asking for write access it does not need would be a larger permission
  /// than the feature justifies.
  Future<bool> hasPermission() =>
      FlutterContacts.permissions.has(PermissionType.read);

  /// Asks for permission, showing the OS prompt.
  ///
  /// The caller is expected to have explained why first — a permission
  /// dialog with no preceding context is the most common reason people
  /// decline one they would otherwise accept.
  Future<bool> requestPermission() async {
    final status =
        await FlutterContacts.permissions.request(PermissionType.read);
    return status == PermissionStatus.granted ||
        // iOS 18 can grant access to a subset of contacts. Partial access is
        // still usable here: matching works on whatever was shared.
        status == PermissionStatus.limited;
  }

  /// Reads and hashes the address book without uploading.
  ///
  /// Separated from [sync] so the count can be shown to the user before
  /// anything leaves the device.
  Future<Set<String>> _collectHashes() async {
    final salt = await _salt();

    // Phone numbers only. Names, photos, emails and addresses are never
    // needed for matching, and not requesting them means they are never held
    // in memory at all — the narrowest read the task allows.
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.phone},
    );

    final raw = <String>[];
    for (final contact in contacts) {
      for (final phone in contact.phones) {
        if (phone.number.trim().isEmpty) continue;
        raw.add(phone.number);
      }
    }

    // From here on only digests exist; `raw` goes out of scope with the
    // method.
    return PhoneNormalizer.hashAll(raw, salt);
  }

  /// Hashes the address book and uploads the digests.
  ///
  /// Returns null when permission is not granted, so the caller can route to
  /// the explanation screen rather than treating it as a failure.
  Future<SyncResult?> sync({bool replace = true}) async {
    if (!await hasPermission()) return null;

    final hashes = await _collectHashes();
    if (hashes.isEmpty) {
      // An empty book is still worth sending when replacing: it is how a
      // user who deleted all their contacts gets the server to match.
      return _repository.sync(const {}, replace: replace);
    }

    if (kDebugMode) {
      debugPrint('[contacts] uploading ${hashes.length} digests');
    }
    return _repository.sync(hashes, replace: replace);
  }

  /// How many contacts would be synced, without sending anything.
  Future<int> previewCount() async {
    if (!await hasPermission()) return 0;
    return (await _collectHashes()).length;
  }

  /// Forgets the locally cached salt.
  ///
  /// Called on opt-out so the device stops being able to reproduce the
  /// digests it previously computed.
  Future<void> forgetSalt() => _storage.delete(key: _saltKey);
}
