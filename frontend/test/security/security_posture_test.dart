import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/features/security/domain/security_posture.dart';

/// A security score is the easiest thing in a product to fake: pick weights,
/// show a reassuring number, and the user learns nothing while feeling safer.
/// These tests are mostly about the ways this one refuses to flatter.
void main() {
  final now = DateTime.utc(2026, 8, 17, 12);

  ActiveSession session({
    String id = 's1',
    bool current = false,
    DateTime? lastActive,
    String? name = 'Pixel 8',
  }) =>
      ActiveSession(
        id: id,
        ipAddress: '203.0.113.7',
        createdAt: now.subtract(const Duration(days: 30)),
        isCurrent: current,
        deviceName: name,
        deviceType: 'android',
        lastActiveAt: lastActive ?? now,
      );

  SecurityPosture posture({
    List<ActiveSession>? sessions,
    bool? encryption = true,
    bool? keywordsLocal = true,
    bool? cloudOcr = false,
  }) =>
      SecurityPosture.from(
        sessions: sessions ?? [session(current: true)],
        now: now,
        encryptionDefault: encryption,
        keywordsAreLocal: keywordsLocal,
        cloudOcrEnabled: cloudOcr,
      );

  List<String> codes(SecurityPosture p) =>
      p.findings.map((f) => f.code).toList();

  group('the level is set by the worst finding', () {
    test('a clean account rates high', () {
      expect(posture().level, SecurityLevel.high);
    });

    test('one critical finding drops it to low, whatever else is fine', () {
      // Averaging would let four reassuring facts bury one critical one, which
      // is the failure mode of every score that tells users what they want.
      final p = posture(encryption: false);
      expect(p.level, SecurityLevel.low);
      expect(codes(p), contains('encryption_not_default'));
    });

    test('a warning alone rates medium', () {
      final p = posture(sessions: [
        session(current: true),
        session(id: 's2', lastActive: now.subtract(const Duration(days: 40))),
      ]);
      expect(p.level, SecurityLevel.medium);
    });

    test('good facts never raise the level above its worst finding', () {
      final p = posture(
        encryption: false,
        keywordsLocal: true,
        cloudOcr: false,
        sessions: [session(current: true)],
      );
      expect(p.findings.where((f) => f.severity == FindingSeverity.informational),
          isNotEmpty);
      expect(p.level, SecurityLevel.low);
    });
  });

  group('what it says about other devices', () {
    test('states that they exist, even when nothing looks wrong', () {
      // "You are signed in on four devices" is the most useful thing this
      // screen can tell someone whose account was taken. Saying it only when it
      // looks suspicious means never saying it when it matters.
      final p = posture(sessions: [
        session(current: true),
        session(id: 's2'),
      ]);
      expect(codes(p), contains('other_devices_signed_in'));
      expect(p.level, SecurityLevel.high, reason: 'normal, not a problem');
    });

    test('says nothing when this is the only device', () {
      expect(codes(posture()), isNot(contains('other_devices_signed_in')));
    });

    test('never counts the current session as another device', () {
      final p = posture(sessions: [session(current: true)]);
      expect(p.otherSessions, isEmpty);
    });

    test('a long-idle device is a warning, not an alarm', () {
      // A tablet used monthly is not a compromise, and calling it one teaches
      // the user to dismiss warnings.
      final p = posture(sessions: [
        session(current: true),
        session(id: 's2', lastActive: now.subtract(const Duration(days: 20))),
      ]);
      final stale = p.findings.firstWhere((f) => f.code == 'stale_session');
      expect(stale.severity, FindingSeverity.warning);
      expect(stale.action, SecurityAction.revokeOtherSessions);
    });

    test('two weeks is the line', () {
      expect(
        session(lastActive: now.subtract(const Duration(days: 13))).isStale(now),
        isFalse,
      );
      expect(
        session(lastActive: now.subtract(const Duration(days: 15))).isStale(now),
        isTrue,
      );
    });

    test('a session that has never been active falls back to its creation', () {
      final never = ActiveSession(
        id: 's3',
        ipAddress: '203.0.113.9',
        createdAt: now.subtract(const Duration(days: 60)),
        isCurrent: false,
      );
      expect(never.isStale(now), isTrue);
    });
  });

  group('honest absence', () {
    test('an unestablished signal produces no finding at all', () {
      // Not a default that flatters the score. If the caller cannot determine
      // whether encryption is on, the screen says nothing about encryption.
      final p = posture(encryption: null, keywordsLocal: null, cloudOcr: null);
      expect(codes(p), isNot(contains('encryption_on')));
      expect(codes(p), isNot(contains('encryption_not_default')));
      expect(codes(p), isNot(contains('keywords_stay_on_device')));
      expect(codes(p), isNot(contains('cloud_ocr_enabled')));
    });

    test('an unknown encryption state does not lower the rating either', () {
      // Absence is not evidence of a problem any more than of safety.
      expect(posture(encryption: null).level, SecurityLevel.high);
    });
  });

  group('privacy facts are stated, not just promised', () {
    test('keywords staying on the device is surfaced', () {
      expect(codes(posture()), contains('keywords_stay_on_device'));
    });

    test('cloud OCR being on is a warning, because the user chose it', () {
      final p = posture(cloudOcr: true);
      expect(codes(p), contains('cloud_ocr_enabled'));
      expect(p.level, SecurityLevel.medium);
    });

    test('cloud OCR off says nothing — it is the default', () {
      expect(codes(posture(cloudOcr: false)), isNot(contains('cloud_ocr_enabled')));
    });
  });

  group('findings are localizable', () {
    test('every code is an identifier, never a sentence', () {
      // A finding that cannot be translated will be shown in English to an
      // Arabic-speaking user.
      final p = posture(
        encryption: false,
        cloudOcr: true,
        sessions: [
          session(current: true),
          session(id: 's2', lastActive: now.subtract(const Duration(days: 40))),
        ],
      );
      expect(p.findings, isNotEmpty);
      for (final f in p.findings) {
        expect(f.code, matches(r'^[a-z][a-z0-9_]*$'), reason: f.code);
        expect(f.code, isNot(contains(' ')));
      }
    });

    test('every action maps to an endpoint that already exists', () {
      // A security screen that can perform arbitrary operations is an attack
      // surface. The set is closed on purpose.
      expect(SecurityAction.values.toSet(), {
        SecurityAction.revokeSession,
        SecurityAction.revokeOtherSessions,
        SecurityAction.reviewSessions,
      });
    });
  });

  group('reading the server contract', () {
    test('parses exactly what /auth/sessions returns', () {
      final s = ActiveSession.fromJson({
        'id': 'abc',
        'device_type': 'android',
        'device_name': 'Pixel 8',
        'ip_address': '203.0.113.7',
        'geo_city': 'Cairo',
        'created_at': '2026-08-01T10:00:00Z',
        'last_active_at': '2026-08-17T09:30:00Z',
        'is_current': true,
      });

      expect(s.id, 'abc');
      expect(s.deviceName, 'Pixel 8');
      expect(s.geoCity, 'Cairo');
      expect(s.isCurrent, isTrue);
      expect(s.lastActiveAt, DateTime.utc(2026, 8, 17, 9, 30));
    });

    test('survives the nullable fields being null', () {
      final s = ActiveSession.fromJson({
        'id': 'abc',
        'device_type': null,
        'device_name': null,
        'ip_address': '203.0.113.7',
        'geo_city': null,
        'created_at': '2026-08-01T10:00:00Z',
        'last_active_at': null,
        'is_current': false,
      });
      expect(s.displayName, isNull);
      expect(s.lastActiveAt, isNull);
    });

    test('falls back through name then type, never to the IP', () {
      // An IP is not a device name. Showing one invites the user to treat a
      // number they cannot interpret as identification.
      expect(session(name: 'Pixel 8').displayName, 'Pixel 8');
      expect(session(name: null).displayName, 'android');

      final bare = ActiveSession(
        id: 's4',
        ipAddress: '203.0.113.7',
        createdAt: now,
        isCurrent: false,
      );
      expect(bare.displayName, isNull);
      expect(bare.displayName, isNot(contains('203')));
    });
  });
}
