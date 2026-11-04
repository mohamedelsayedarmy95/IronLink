import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Reduces a phone number to the one form both sides hash.
///
/// This is a deliberate duplicate of `app/services/contact_discovery.py`.
/// The two implementations must stay identical: if a number normalizes
/// differently here than on the server, its hash differs, the contact simply
/// never matches, and nothing anywhere reports an error. That silence is why
/// the rules are spelled out rather than approximated, and why the shared
/// test vectors at the bottom of this file exist.
///
/// Any change here is a change to the wire format and must land on both sides
/// together.
class PhoneNormalizer {
  const PhoneNormalizer._();

  /// E.164 permits at most 15 digits.
  static const maxDigits = 15;
  static const minDigits = 7;

  /// Country assumed for numbers written in local form. Egypt, matching the
  /// server's DEFAULT_COUNTRY_CODE.
  static const defaultCountryCode = '20';

  /// National trunk prefixes stripped when promoting a local number.
  static const trunkPrefixes = ['0'];

  static final _nonDigits = RegExp(r'[^\d+]');

  /// Returns the number as `+<digits>`, or null when it cannot be one.
  ///
  /// Null rather than throwing: an address book routinely holds entries that
  /// are not phone numbers, and one of them must not fail the whole sync.
  static String? normalize(String raw, {String? defaultCountry}) {
    final country = defaultCountry ?? defaultCountryCode;
    if (raw.isEmpty) return null;

    final cleaned = raw.trim().replaceAll(_nonDigits, '');
    if (cleaned.isEmpty) return null;

    final explicitInternational = cleaned.startsWith('+');
    var digits = cleaned.replaceAll('+', '');

    if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) return null;

    if (!explicitInternational) {
      if (digits.startsWith('00')) {
        // 00 is the other way of writing '+'.
        digits = digits.substring(2);
      } else {
        var strippedTrunk = false;
        for (final prefix in trunkPrefixes) {
          if (digits.startsWith(prefix)) {
            digits = digits.substring(prefix.length);
            strippedTrunk = true;
            break;
          }
        }

        // A number with no '+', no '00' and no trunk prefix is ambiguous:
        // "201099695779" could be local and needing a country code, or
        // international written without its '+'. Reading it as local would
        // prepend the code twice and produce a number matching nothing, so
        // it counts as already-international when it starts with the country
        // code and the remainder is a plausible national number.
        final alreadyInternational = !strippedTrunk &&
            digits.startsWith(country) &&
            digits.length >= minDigits &&
            digits.length <= maxDigits &&
            digits.length > country.length + 6;

        if (!alreadyInternational) {
          digits = '$country$digits';
        }
      }
    }

    if (digits.length < minDigits || digits.length > maxDigits) return null;
    // A leading zero here means the trunk prefix was never stripped, so this
    // is not valid E.164.
    if (digits.startsWith('0')) return null;

    return '+$digits';
  }

  /// Salted SHA-256, hex-encoded — the same construction the server uses.
  ///
  /// The salt is prefixed rather than applied via HMAC only so the two
  /// implementations can be trivially identical; the property that matters
  /// is that the salt is secret and absent from the database.
  static String hash(String e164, String salt) =>
      sha256.convert(utf8.encode('$salt$e164')).toString();

  /// Normalizes and hashes a whole address book in one pass.
  ///
  /// Returns digests only. The raw numbers stay in the caller's memory and
  /// are never returned, logged, or persisted — the point of doing this on
  /// the device is that they have nowhere else to go.
  static Set<String> hashAll(Iterable<String> rawNumbers, String salt) {
    final digests = <String>{};
    for (final raw in rawNumbers) {
      final e164 = normalize(raw);
      if (e164 == null) continue;
      digests.add(hash(e164, salt));
    }
    return digests;
  }
}

/// Cases that must produce identical results on both sides.
///
/// Kept in the source rather than only in tests so the contract is visible to
/// anyone editing the rules above.
const phoneNormalizationVectors = <String, String?>{
  '01099695779': '+201099695779',
  '+201099695779': '+201099695779',
  '00201099695779': '+201099695779',
  '201099695779': '+201099695779',
  '1099695779': '+201099695779',
  '+20 (109) 969-5779': '+201099695779',
  ' 010 9969 5779 ': '+201099695779',
  '+966501234567': '+966501234567',
  '+14155551234': '+14155551234',
  'not a phone': null,
  'email@example.com': null,
  '+1234': null,
  '': null,
};
