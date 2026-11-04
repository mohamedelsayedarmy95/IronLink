import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one set of options every [FlutterSecureStorage] in this app must use.
///
/// This exists because getting it wrong is silent and destructive. On Android
/// the plugin keeps everything in a single preferences file, and the two
/// backends — plain, and AndroidX EncryptedSharedPreferences — cannot read
/// each other's entries. Two instances configured differently therefore fight
/// over the same file: whichever writes last makes the other's data
/// unreadable, with no error anywhere.
///
/// That is not hypothetical. Storing Signal keys with
/// `encryptedSharedPreferences: true` while the API client used the default
/// wiped the auth token on a real device: the key publish that runs at login
/// got a 401 because the token it had just saved read back as null, and the
/// session was gone on the next launch. The app looked like it had simply
/// logged the user out.
///
/// So: one definition, used everywhere. If a new call site needs storage, it
/// uses this.
const ironSecureStorage = FlutterSecureStorage(
  // Encrypted rather than the default, because this file holds Signal
  // identity keys and session tokens. On a rooted device the plain backend's
  // contents are readable.
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);
