import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth_repository.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class PhoneSubmitted extends AuthEvent {
  const PhoneSubmitted(this.phoneNumber);
  final String phoneNumber;
  @override
  List<Object?> get props => [phoneNumber];
}

class OtpChanged extends AuthEvent {
  const OtpChanged(this.code);
  final String code;
  @override
  List<Object?> get props => [code];
}

class MilitaryIdSubmitted extends AuthEvent {
  const MilitaryIdSubmitted(this.militaryId);
  final String militaryId;
  @override
  List<Object?> get props => [militaryId];
}

class ResendOtpRequested extends AuthEvent {
  const ResendOtpRequested();
}

class _CountdownTicked extends AuthEvent {
  const _CountdownTicked(this.secondsLeft);
  final int secondsLeft;
  @override
  List<Object?> get props => [secondsLeft];
}

class _CodeSent extends AuthEvent {
  const _CodeSent(this.verificationId, this.resendToken);
  final String verificationId;
  final int? resendToken;
  @override
  List<Object?> get props => [verificationId, resendToken];
}

/// Android auto-retrieval confirmed the SMS code without the user typing it —
/// skip straight to the military-ID step, already holding a valid ID token.
class _PhoneAutoVerified extends AuthEvent {
  const _PhoneAutoVerified(this.idToken);
  final String idToken;
  @override
  List<Object?> get props => [idToken];
}

class _PhoneVerificationFailed extends AuthEvent {
  const _PhoneVerificationFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ── State ─────────────────────────────────────────────────────────────────────

enum AuthStep { phone, otp, militaryId }

enum AuthStatus { idle, loading, error, success }

class AuthState extends Equatable {
  const AuthState({
    this.step = AuthStep.phone,
    this.status = AuthStatus.idle,
    this.phoneNumber = '',
    this.otpCode = '',
    this.resendCountdown = 0,
    this.errorMessage,
    this.user,
    this.verificationId,
    this.resendToken,
    this.idToken,
  });

  final AuthStep step;
  final AuthStatus status;
  final String phoneNumber;
  final String otpCode;
  final int resendCountdown;
  final String? errorMessage;
  final AuthUser? user;

  // Firebase Phone Auth session state
  final String? verificationId; // ties a typed OTP back to the sent SMS
  final int? resendToken;       // lets "resend" reuse the same SMS session
  final String? idToken;        // set only when Android auto-verified the code

  bool get canResend => resendCountdown == 0;

  AuthState copyWith({
    AuthStep? step,
    AuthStatus? status,
    String? phoneNumber,
    String? otpCode,
    int? resendCountdown,
    String? errorMessage,
    AuthUser? user,
    String? verificationId,
    int? resendToken,
    String? idToken,
    bool clearIdToken = false,
  }) =>
      AuthState(
        step: step ?? this.step,
        status: status ?? this.status,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        otpCode: otpCode ?? this.otpCode,
        resendCountdown: resendCountdown ?? this.resendCountdown,
        errorMessage: errorMessage,
        user: user ?? this.user,
        verificationId: verificationId ?? this.verificationId,
        resendToken: resendToken ?? this.resendToken,
        idToken: clearIdToken ? null : (idToken ?? this.idToken),
      );

  @override
  List<Object?> get props => [
        step,
        status,
        phoneNumber,
        otpCode,
        resendCountdown,
        errorMessage,
        user?.id,
        verificationId,
        idToken,
      ];
}

// ── Bloc ──────────────────────────────────────────────────────────────────────

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repo, {required this.deviceFingerprint})
      : super(const AuthState()) {
    on<PhoneSubmitted>(_onPhoneSubmitted);
    on<OtpChanged>(_onOtpChanged);
    on<MilitaryIdSubmitted>(_onMilitaryIdSubmitted);
    on<ResendOtpRequested>(_onResendRequested);
    on<_CodeSent>(_onCodeSent);
    on<_PhoneAutoVerified>(_onPhoneAutoVerified);
    on<_PhoneVerificationFailed>((e, emit) => emit(state.copyWith(
        status: AuthStatus.error, errorMessage: e.message)));
    on<_CountdownTicked>(
        (e, emit) => emit(state.copyWith(resendCountdown: e.secondsLeft)));
  }

  final AuthRepository _repo;
  final String deviceFingerprint;
  Timer? _countdown;

  Future<void> _onPhoneSubmitted(
      PhoneSubmitted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(
        status: AuthStatus.loading, phoneNumber: event.phoneNumber));
    try {
      await _repo.sendPhoneOtp(
        phoneNumber: event.phoneNumber,
        forceResendingToken: state.resendToken,
        onCodeSent: (verificationId, resendToken) =>
            add(_CodeSent(verificationId, resendToken)),
        onAutoVerified: (idToken) => add(_PhoneAutoVerified(idToken)),
        onError: (message) => add(_PhoneVerificationFailed(message)),
      );
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: AuthRepository.firebaseErrorMessage(e),
      ));
    }
  }

  void _onCodeSent(_CodeSent event, Emitter<AuthState> emit) {
    emit(state.copyWith(
      step: AuthStep.otp,
      status: AuthStatus.idle,
      verificationId: event.verificationId,
      resendToken: event.resendToken,
      resendCountdown: 60,
    ));
    _startCountdown(60);
  }

  void _onPhoneAutoVerified(_PhoneAutoVerified event, Emitter<AuthState> emit) {
    // Android confirmed the SMS code itself — skip straight to military ID,
    // already holding a valid Firebase ID token.
    emit(state.copyWith(
      step: AuthStep.militaryId,
      status: AuthStatus.idle,
      idToken: event.idToken,
    ));
  }

  // Fable5-Enhancement: entering the 6th OTP digit advances AUTOMATICALLY to
  // the military-ID step — no extra "next" button.
  void _onOtpChanged(OtpChanged event, Emitter<AuthState> emit) {
    emit(state.copyWith(otpCode: event.code, status: AuthStatus.idle));
    if (event.code.length == 6) {
      emit(state.copyWith(step: AuthStep.militaryId));
    }
  }

  Future<void> _onMilitaryIdSubmitted(
      MilitaryIdSubmitted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.loading));
    try {
      // Auto-verification already produced an ID token; otherwise exchange
      // the manually-typed OTP for one now.
      final idToken = state.idToken ??
          await _repo.confirmOtp(
            verificationId: state.verificationId!,
            otpCode: state.otpCode,
          );
      final user = await _repo.exchangeFirebaseToken(
        idToken: idToken,
        militaryId: event.militaryId,
        deviceFingerprint: deviceFingerprint,
      );
      emit(state.copyWith(status: AuthStatus.success, user: user));
    } catch (e) {
      // Firebase codes are single-use — return to OTP step so the user gets
      // a fresh one instead of retrying a burned code.
      emit(state.copyWith(
        step: AuthStep.otp,
        status: AuthStatus.error,
        otpCode: '',
        clearIdToken: true,
        errorMessage: AuthRepository.firebaseErrorMessage(e),
      ));
    }
  }

  Future<void> _onResendRequested(
      ResendOtpRequested event, Emitter<AuthState> emit) async {
    if (!state.canResend) return;
    add(PhoneSubmitted(state.phoneNumber));
  }

  void _startCountdown(int seconds) {
    _countdown?.cancel();
    var left = seconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      left -= 1;
      if (left <= 0) {
        t.cancel();
        add(const _CountdownTicked(0));
      } else {
        add(_CountdownTicked(left));
      }
    });
  }

  @override
  Future<void> close() {
    _countdown?.cancel();
    return super.close();
  }
}
