import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/failure.dart';
import '../domain/security_posture.dart';
import '../security_repository.dart';

/// State for the Security Center.
///
/// The posture is recomputed from the server's session list on every load
/// rather than cached and patched. A security screen showing a stale session
/// list is worse than one showing a spinner: the user makes a decision about
/// who has access to their account based on what is in front of them.

sealed class SecurityEvent extends Equatable {
  const SecurityEvent();

  @override
  List<Object?> get props => const [];
}

class SecurityRequested extends SecurityEvent {
  const SecurityRequested();
}

class SessionRevoked extends SecurityEvent {
  const SessionRevoked(this.sessionId);

  final String sessionId;

  @override
  List<Object?> get props => [sessionId];
}

/// "Secure my account" — sign out every other device.
class OtherSessionsRevoked extends SecurityEvent {
  const OtherSessionsRevoked();
}

class SecurityState extends Equatable {
  const SecurityState({
    this.posture,
    this.loading = false,
    this.working = false,
    this.failure,
    this.partialFailureCount = 0,
  });

  final SecurityPosture? posture;

  /// First load, or a reload. The screen shows a spinner rather than stale
  /// sessions.
  final bool loading;

  /// A revoke is in flight. Distinct from [loading] so the action can be
  /// disabled without the whole list disappearing underneath the user.
  final bool working;

  final NetworkFailure? failure;

  /// How many devices could not be signed out during "secure my account".
  ///
  /// Surfaced rather than swallowed: telling someone their account is secured
  /// when one device is still signed in would be the worst possible lie for
  /// this screen to tell.
  final int partialFailureCount;

  bool get hasData => posture != null;

  SecurityState copyWith({
    SecurityPosture? posture,
    bool? loading,
    bool? working,
    NetworkFailure? failure,
    bool clearFailure = false,
    int? partialFailureCount,
  }) =>
      SecurityState(
        posture: posture ?? this.posture,
        loading: loading ?? this.loading,
        working: working ?? this.working,
        failure: clearFailure ? null : (failure ?? this.failure),
        partialFailureCount: partialFailureCount ?? this.partialFailureCount,
      );

  @override
  List<Object?> get props =>
      [posture?.level, posture?.sessions.length, posture?.findings.length,
       loading, working, failure, partialFailureCount];
}

class SecurityBloc extends Bloc<SecurityEvent, SecurityState> {
  SecurityBloc(
    this._repo, {
    DateTime Function()? now,
    this.encryptionDefault,
    this.keywordsAreLocal,
    this.cloudOcrEnabled,
  })  : _now = now ?? (() => DateTime.now().toUtc()),
        super(const SecurityState()) {
    on<SecurityRequested>(_onRequested);
    on<SessionRevoked>(_onRevoked);
    on<OtherSessionsRevoked>(_onRevokedOthers);
  }

  final SecurityRepository _repo;
  final DateTime Function() _now;

  /// Facts this bloc is told rather than discovers.
  ///
  /// Null means "not established", and the posture then says nothing about it.
  /// A default of true here would be the screen flattering itself about the
  /// product's central claim.
  final bool? encryptionDefault;
  final bool? keywordsAreLocal;
  final bool? cloudOcrEnabled;

  Future<void> _onRequested(
    SecurityRequested event,
    Emitter<SecurityState> emit,
  ) async {
    emit(state.copyWith(loading: true, clearFailure: true));
    await _load(emit);
  }

  Future<void> _onRevoked(
    SessionRevoked event,
    Emitter<SecurityState> emit,
  ) async {
    emit(state.copyWith(working: true, clearFailure: true));
    try {
      await _repo.revoke(event.sessionId);
    } catch (e) {
      emit(state.copyWith(
        working: false,
        failure: NetworkFailureClassifier.from(e),
      ));
      return;
    }
    // Reloaded from the server rather than removed locally. If the revoke
    // half-succeeded, the list must show what is true, not what was intended.
    await _load(emit);
  }

  Future<void> _onRevokedOthers(
    OtherSessionsRevoked event,
    Emitter<SecurityState> emit,
  ) async {
    final current = state.posture;
    if (current == null) return;

    emit(state.copyWith(working: true, clearFailure: true, partialFailureCount: 0));
    List<String> failed;
    try {
      failed = await _repo.revokeOthers(current.sessions);
    } catch (e) {
      emit(state.copyWith(
        working: false,
        failure: NetworkFailureClassifier.from(e),
      ));
      return;
    }
    await _load(emit, partialFailureCount: failed.length);
  }

  Future<void> _load(
    Emitter<SecurityState> emit, {
    int partialFailureCount = 0,
  }) async {
    try {
      final sessions = await _repo.sessions();
      emit(state.copyWith(
        posture: SecurityPosture.from(
          sessions: sessions,
          now: _now(),
          encryptionDefault: encryptionDefault,
          keywordsAreLocal: keywordsAreLocal,
          cloudOcrEnabled: cloudOcrEnabled,
        ),
        loading: false,
        working: false,
        clearFailure: true,
        partialFailureCount: partialFailureCount,
      ));
    } catch (e) {
      emit(state.copyWith(
        loading: false,
        working: false,
        failure: NetworkFailureClassifier.from(e),
        partialFailureCount: partialFailureCount,
      ));
    }
  }
}
