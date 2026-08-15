import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key-value storage for private key material.
///
/// An interface rather than a direct dependency on flutter_secure_storage so
/// the protocol store can be exercised in tests, which have no platform
/// channels. The production implementation is the only one that touches disk.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Keys currently held, used to enumerate sessions and pre-keys.
  Future<Set<String>> keys();
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // Without this, values land in plain SharedPreferences on
              // Android, which any process with the same UID — and any rooted
              // device — can read. Private keys must not sit there.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Set<String>> keys() async => (await _storage.readAll()).keys.toSet();
}

/// In-memory implementation for tests.
class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<Set<String>> keys() async => _values.keys.toSet();
}
