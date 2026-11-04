import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/features/security/bloc/security_bloc.dart';
import 'package:ironlink/features/security/domain/security_posture.dart';
import 'package:ironlink/features/security/security_repository.dart';

/// The bloc's job is to make sure the screen never shows a session list that
/// disagrees with the server. Someone decides who has access to their account
/// from what is in front of them, so a stale list is worse than a spinner.
void main() {
  final now = DateTime.utc(2026, 8, 17, 12);

  ActiveSession session(String id, {bool current = false, int idleDays = 0}) =>
      ActiveSession(
        id: id,
        ipAddress: '203.0.113.7',
        createdAt: now.subtract(const Duration(days: 30)),
        isCurrent: current,
        deviceName: 'Device $id',
        lastActiveAt: now.subtract(Duration(days: idleDays)),
      );

  SecurityBloc blocFor(_FakeRepository repo, {bool? encryption = true}) =>
      SecurityBloc(repo, now: () => now, encryptionDefault: encryption);

  /// Waits for the bloc to finish reacting to an event.
  ///
  /// [minTurns] is not padding. Immediately after `add`, the bloc has not yet
  /// emitted `working: true`, so a predicate of "not working" is satisfied by
  /// the *previous* state and the helper returns before anything has happened.
  /// That produced three tests that passed against work never done — the kind
  /// of green that is worse than red. Turning the loop over a few times first
  /// lets the handler start before its completion is judged.
  Future<SecurityState> settle(
    SecurityBloc bloc, {
    bool Function(SecurityState)? until,
    int minTurns = 25,
  }) async {
    final test = until ?? (s) => !s.loading && !s.working;
    for (var i = 0; i < 600; i++) {
      await Future<void>.delayed(Duration.zero);
      if (i < minTurns) continue;
      if (test(bloc.state) && bloc.state != const SecurityState()) {
        return bloc.state;
      }
    }
    return bloc.state;
  }

  group('loading', () {
    test('turns the server list into a posture', () async {
      final repo = _FakeRepository(sessions: [
        session('a', current: true),
        session('b'),
      ]);
      final bloc = blocFor(repo);

      bloc.add(const SecurityRequested());
      final state = await settle(bloc);

      expect(state.hasData, isTrue);
      expect(state.posture!.sessions, hasLength(2));
      expect(state.posture!.otherSessions, hasLength(1));
      await bloc.close();
    });

    test('a failure leaves no posture rather than an empty one', () async {
      // An empty session list would read as "no other devices are signed in",
      // which is a claim, and the wrong one.
      final repo = _FakeRepository(failOnList: true);
      final bloc = blocFor(repo);

      bloc.add(const SecurityRequested());
      final state = await settle(bloc);

      expect(state.hasData, isFalse);
      expect(state.failure, isNotNull);
      await bloc.close();
    });

    test('passes the facts it was told into the posture', () async {
      final repo = _FakeRepository(sessions: [session('a', current: true)]);
      final bloc = blocFor(repo, encryption: false);

      bloc.add(const SecurityRequested());
      final state = await settle(bloc);

      expect(state.posture!.level, SecurityLevel.low);
      await bloc.close();
    });

    test('an unestablished fact stays unestablished', () async {
      final repo = _FakeRepository(sessions: [session('a', current: true)]);
      final bloc = SecurityBloc(repo, now: () => now); // no facts supplied

      bloc.add(const SecurityRequested());
      final state = await settle(bloc);

      final codes = state.posture!.findings.map((f) => f.code);
      expect(codes, isNot(contains('encryption_on')));
      expect(codes, isNot(contains('encryption_not_default')));
      await bloc.close();
    });
  });

  group('revoking one device', () {
    test('re-reads from the server rather than removing it locally', () async {
      // If the revoke half-succeeded, the list has to show what is true, not
      // what was intended.
      final repo = _FakeRepository(sessions: [
        session('a', current: true),
        session('b'),
      ]);
      final bloc = blocFor(repo);
      bloc.add(const SecurityRequested());
      await settle(bloc);

      bloc.add(const SessionRevoked('b'));
      final state = await settle(bloc, until: (s) => !s.working && s.hasData);

      expect(repo.revoked, ['b']);
      expect(repo.listCalls, 2, reason: 'reloaded after the revoke');
      expect(state.posture!.sessions.map((s) => s.id), ['a']);
      await bloc.close();
    });

    test('a failed revoke reports it and keeps the list intact', () async {
      final repo = _FakeRepository(
        sessions: [session('a', current: true), session('b')],
        failOnRevoke: true,
      );
      final bloc = blocFor(repo);
      bloc.add(const SecurityRequested());
      await settle(bloc);

      bloc.add(const SessionRevoked('b'));
      final state = await settle(bloc, until: (s) => s.failure != null);

      expect(state.failure, isNotNull);
      expect(state.posture!.sessions, hasLength(2),
          reason: 'nothing was removed, because nothing was revoked');
      await bloc.close();
    });
  });

  group('secure my account', () {
    test('revokes every other device and never the current one', () async {
      final repo = _FakeRepository(sessions: [
        session('a', current: true),
        session('b'),
        session('c'),
      ]);
      final bloc = blocFor(repo);
      bloc.add(const SecurityRequested());
      await settle(bloc);

      bloc.add(const OtherSessionsRevoked());
      final state = await settle(bloc, until: (s) => !s.working && s.hasData);

      expect(repo.revoked, ['b', 'c']);
      expect(repo.revoked, isNot(contains('a')));
      expect(state.posture!.otherSessions, isEmpty);
      await bloc.close();
    });

    test('a partial result is counted, not hidden', () async {
      // Telling someone their account is secured while a device is still
      // signed in would be the worst lie this screen could tell.
      final repo = _FakeRepository(
        sessions: [
          session('a', current: true),
          session('b'),
          session('c'),
        ],
        failRevokeIds: {'c'},
      );
      final bloc = blocFor(repo);
      bloc.add(const SecurityRequested());
      await settle(bloc);

      bloc.add(const OtherSessionsRevoked());
      final state =
          await settle(bloc, until: (s) => !s.working && s.partialFailureCount > 0);

      expect(state.partialFailureCount, 1);
      await bloc.close();
    });

    test('one failure does not stop the others being signed out', () async {
      final repo = _FakeRepository(
        sessions: [
          session('a', current: true),
          session('b'),
          session('c'),
          session('d'),
        ],
        failRevokeIds: {'b'},
      );
      final bloc = blocFor(repo);
      bloc.add(const SecurityRequested());
      await settle(bloc);

      bloc.add(const OtherSessionsRevoked());
      await settle(bloc, until: (s) => !s.working && s.hasData);

      expect(repo.revoked, containsAll(['c', 'd']));
      await bloc.close();
    });

    test('does nothing before the first load', () async {
      // There is no session list to act on, and inventing one would mean
      // revoking whatever happened to be cached.
      final repo = _FakeRepository(sessions: [session('a', current: true)]);
      final bloc = blocFor(repo);

      bloc.add(const OtherSessionsRevoked());
      await Future<void>.delayed(Duration.zero);

      expect(repo.revoked, isEmpty);
      await bloc.close();
    });
  });

}

class _FakeRepository extends SecurityRepository {
  _FakeRepository({
    List<ActiveSession> sessions = const [],
    this.failOnList = false,
    this.failOnRevoke = false,
    this.failRevokeIds = const {},
  })  : _stored = sessions,
        super(_UnusedApi());

  /// The server's state, mutated by revoke so a reload reflects what happened
  /// rather than what was asked for — which is the property under test.
  List<ActiveSession> _stored;

  final bool failOnList;
  final bool failOnRevoke;
  final Set<String> failRevokeIds;

  final List<String> revoked = [];
  int listCalls = 0;

  @override
  Future<List<ActiveSession>> sessions() async {
    listCalls++;
    if (failOnList) throw Exception('offline');
    return List.unmodifiable(_stored);
  }

  @override
  Future<void> revoke(String sessionId) async {
    if (failOnRevoke || failRevokeIds.contains(sessionId)) {
      throw Exception('revoke failed');
    }
    revoked.add(sessionId);
    _stored = _stored.where((s) => s.id != sessionId).toList();
  }
}

/// The fake never reaches the network, so the client is never used. Present
/// only because the real repository requires one.
class _UnusedApi extends ApiClient {
  _UnusedApi();
}
