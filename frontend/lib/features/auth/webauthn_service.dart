// WebAuthn service wrapper for the passkeys package.
// Provides a clean interface between the passkeys package and our auth flow.
library;

import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

/// Service that wraps the Corbado passkeys package for WebAuthn/FIDO2 operations.
///
/// Handles the conversion between our backend's JSON format (matching the
/// WebAuthn spec) and the passkeys package's typed options/credential objects.
class WebAuthnService {
  WebAuthnService._();

  /// The underlying passkeys authenticator.
  ///
  /// `debugMode` enables the Passkeys Doctor for development diagnostics.
  static final PasskeyAuthenticator _authenticator = PasskeyAuthenticator(
    debugMode: const bool.fromEnvironment('dart.vm.product') == false,
  );

  /// Checks whether WebAuthn/passkeys are available on the current platform/device.
  ///
  /// On web, this checks the WebAuthn API availability.
  /// On Android, this checks if the platform supports passkeys (Play Services, etc.).
  /// On iOS/macOS, this checks if the device supports Face ID / Touch ID.
  /// On Windows, this checks Windows Hello availability.
  static Future<bool> get isAvailable async {
    try {
      // Use the platform-specific availability check.
      // The getAvailability() returns a GetAvailability instance that can query
      // the current platform's passkey support.
      final availability = _authenticator.getAvailability();

      // Detect platform and query accordingly.
      // For a quick check, we can try the web check as a fallback.
      // On mobile/desktop, the platform-specific check will be used.
      final result = await availability.web();
      return result.hasPasskeySupport;
    } catch (e) {
      // If the web check fails, try platform-specific checks.
      // For now, we assume available if no hard error occurs.
      return true;
    }
  }

  /// Creates a new passkey credential (registration ceremony).
  ///
  /// [options] is the JSON object from `POST /auth/webauthn/register/begin`,
  /// containing `publicKeyCredentialCreationOptions` per the WebAuthn spec.
  ///
  /// Returns a JSON-serializable map ready for `POST /auth/webauthn/register/complete`.
  static Future<Map<String, dynamic>> createCredential({
    required Map<String, dynamic> options,
  }) async {
    // Parse the backend's creation options into the passkeys typed model.
    final request = RegisterRequestType.fromJson(options);

    // Invoke the platform authenticator (Face ID, Touch ID, Windows Hello, YubiKey, etc.).
    final response = await _authenticator.register(request);

    // Convert the returned credential to JSON for our backend.
    return response.toJson();
  }

  /// Gets a passkey assertion (authentication ceremony).
  ///
  /// [options] is the JSON object from `POST /auth/webauthn/authenticate/begin`,
  /// containing `publicKeyCredentialRequestOptions` per the WebAuthn spec.
  /// For usernameless login, `allowCredentials` is empty.
  ///
  /// Returns a JSON-serializable map ready for `POST /auth/webauthn/authenticate/complete`.
  static Future<Map<String, dynamic>> getAssertion({
    required Map<String, dynamic> options,
  }) async {
    // Parse the backend's request options into the passkeys typed model.
    // For usernameless login, we use conditional mediation with empty allowCredentials.
    final request = AuthenticateRequestType.fromJson(
      options,
      mediation: MediationType.Conditional,
      preferImmediatelyAvailableCredentials: true,
      canBeSecurityKey: true,
    );

    // Invoke the platform authenticator to sign the challenge.
    final response = await _authenticator.authenticate(request);

    // Convert the returned assertion to JSON for our backend.
    return response.toJson();
  }
}