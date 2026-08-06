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
  });

  final AuthStep step;
  final AuthStatus status;
  final String phoneNumber;
  final String otpCode;
  final int resendCountdown;
  final String? errorMessage;
  final AuthUser? user;

  bool get canResend => resendCountdown == 0;

  AuthState copyWith({
    AuthStep? step,
    AuthStatus? status,
    String? phoneNumber,
    String? otpCode,
    int? resendCountdown,
    String? errorMessage,
    AuthUser? user,
  }) =>
      AuthState(
        step: step ?? this.step,
        status: status ?? this.status,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        otpCode: otpCode ?? this.otpCode,
        resendCountdown: resendCountdown ?? this.resendCountdown,
        errorMessage: errorMessage,
        user: user ?? this.user,
      );

  @override
  List<Object?> get props =>
      [step, status, phoneNumber, otpCode, resendCountdown, errorMessage, user?.id];
}

// ── Bloc ──────────────────────────────────────────────────────────────────────

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repo, {required this.deviceFingerprint})
      : super(const AuthState()) {
    on<PhoneSubmitted>(_onPhoneSubmitted);
    on<OtpChanged>(_onOtpChanged);
    on<MilitaryIdSubmitted>(_onMilitaryIdSubmitted);
    on<ResendOtpRequested>(_onResendRequested);
    on<_CountdownTicked>(
        (e, emit) => emit(state.copyWith(resendCountdown: e.secondsLeft)));
  }

  final AuthRepository _repo;
  final String deviceFingerprint;
  Timer? _countdown;

  Future<void> _onPhoneSubmitted(
      PhoneSubmitted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.loading));
    try {
      final retryAfter = await _repo.requestOtp(event.phoneNumber);
      emit(state.copyWith(
        step: AuthStep.otp,
        status: AuthStatus.idle,
        phoneNumber: event.phoneNumber,
        resendCountdown: retryAfter,
      ));
      _startCountdown(retryAfter);
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: AuthRepository.errorMessage(e),
      ));
    }
  }

  // Fable5-Enhancement: entering the 6th OTP digit advances AUTOMATICALLY to
  // the military-ID step — no extra "next" button. One less tap, and the OTP
  // is validated server-side together with the military ID in a single call
  // (fewer round-trips, no oracle telling an attacker "OTP ok, now guess the ID").
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
      final user = await _repo.verify(
        phoneNumber: state.phoneNumber,
        otpCode: state.otpCode,
        militaryId: event.militaryId,
        deviceFingerprint: deviceFingerprint,
      );
      emit(state.copyWith(status: AuthStatus.success, user: user));
    } catch (e) {
      // Server rejects the pair atomically — return to OTP step because the
      // code has been consumed/burned server-side.
      emit(state.copyWith(
        step: AuthStep.otp,
        status: AuthStatus.error,
        otpCode: '',
        errorMessage: AuthRepository.errorMessage(e),
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
