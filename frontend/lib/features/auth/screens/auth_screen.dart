import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/home_screen.dart';
import '../auth_repository.dart';
import '../bloc/auth_bloc.dart';
import 'auth_colors.dart';

/// Animated step-by-step auth: phone → OTP (60s countdown) → military ID.
/// Each step slides in; completed steps collapse to a compact summary row.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (prev, curr) =>
          prev.status != curr.status || prev.step != curr.step,
      listener: (context, state) {
        if (state.status == AuthStatus.error && state.errorCode != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              backgroundColor: AuthColors.surfaceRaised,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AuthColors.border),
              ),
              content: Row(
                children: [
                  const Icon(Icons.gpp_bad_outlined, color: AuthColors.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorText(L.of(context), state.errorCode!, state.errorDetail),
                      style: const TextStyle(color: AuthColors.textHi),
                    ),
                  ),
                ],
              ),
            ));
        }
        if (state.status == AuthStatus.success) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen(user: state.user!)),
            (_) => false,
          );
        }
      },
      builder: (context, state) {
        final t = L.of(context);
        return Scaffold(
          backgroundColor: AuthColors.bg,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.6),
                radius: 1.2,
                colors: [AuthColors.bgVignette, AuthColors.bg],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    _StepDots(step: state.step),
                    const SizedBox(height: 28),
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AuthColors.fill,
                        border: Border.all(color: AuthColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: AuthColors.cyan.withValues(alpha: 0.18),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.shield_outlined,
                          size: 30, color: AuthColors.cyan),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      t.secureSignInTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AuthColors.textHi,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitleFor(t, state.step),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: AuthColors.textLo, height: 1.5),
                    ),
                    const SizedBox(height: 32),

                    // Step 1 — phone
                    _StepContainer(
                      active: state.step == AuthStep.phone,
                      done: state.step != AuthStep.phone,
                      doneLabel: t.phoneNumberLabel,
                      doneSummary: state.phoneNumber,
                      child: const _PhoneStep(),
                    ),

                    // Step 2 — OTP
                    _StepContainer(
                      active: state.step == AuthStep.otp,
                      done: state.step == AuthStep.militaryId,
                      doneLabel: t.otpCodeLabel,
                      doneSummary: '••••••',
                      child: const _OtpStep(),
                    ),

                    // Step 3 — military ID
                    _StepContainer(
                      active: state.step == AuthStep.militaryId,
                      done: false,
                      doneLabel: '',
                      doneSummary: '',
                      child: const _MilitaryIdStep(),
                    ),

                    if (state.status == AuthStatus.loading) ...[
                      const SizedBox(height: 28),
                      const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: AuthColors.cyan,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _subtitleFor(L t, AuthStep step) => switch (step) {
        AuthStep.phone => t.phoneStepSubtitle,
        AuthStep.otp => t.otpStepSubtitle,
        AuthStep.militaryId => t.militaryIdStepSubtitle,
      };

  /// [detail] is the server's own error string (already in whatever language
  /// it replied in) for AuthErrorCode.unexpected when the API sent one;
  /// every other code has a fully localized message of its own.
  static String _errorText(L t, AuthErrorCode code, String? detail) {
    return switch (code) {
      AuthErrorCode.network => t.errorNetwork,
      AuthErrorCode.invalidPhone => t.errorInvalidPhone,
      AuthErrorCode.tooManyRequests => t.errorTooManyRequests,
      AuthErrorCode.invalidCode => t.errorInvalidCode,
      AuthErrorCode.sessionExpired => t.errorSessionExpired,
      AuthErrorCode.phoneVerificationFailed =>
        detail ?? t.errorPhoneVerificationFailed,
      AuthErrorCode.unexpected => detail ?? t.errorUnexpected,
    };
  }
}

/// Three dots tracking progress across the flow — filled/glowing up to the
/// current step, dim afterwards.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final AuthStep step;

  @override
  Widget build(BuildContext context) {
    final index = AuthStep.values.indexOf(step);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < AuthStep.values.length; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: i <= index ? AuthColors.cyan : AuthColors.border,
              boxShadow: i == index
                  ? [
                      BoxShadow(
                        color: AuthColors.cyan.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
          if (i < AuthStep.values.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Wraps a step: animates in when active, collapses to a summary chip when done.
class _StepContainer extends StatelessWidget {
  const _StepContainer({
    required this.active,
    required this.done,
    required this.doneLabel,
    required this.doneSummary,
    required this.child,
  });

  final bool active;
  final bool done;
  final String doneLabel;
  final String doneSummary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (widget, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
              .animate(anim),
          child: widget,
        ),
      ),
      child: active
          ? Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: child,
            )
          : done
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AuthColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AuthColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AuthColors.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(doneLabel,
                                  style: const TextStyle(
                                      color: AuthColors.textLo, fontSize: 11)),
                              Text(doneSummary,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                      color: AuthColors.textHi,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
    );
  }
}

/// Glass-styled input decoration shared by every step.
InputDecoration _glassInput({String? hint, Widget? prefixIcon, Widget? suffixIcon}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AuthColors.textLo),
    filled: true,
    fillColor: AuthColors.surface,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: border(AuthColors.border, 1),
    focusedBorder: border(AuthColors.cyan, 1.6),
    border: border(AuthColors.border, 1),
  );
}

/// Primary CTA button — cyan gradient with glow, matching the welcome screen.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: enabled
                ? const [AuthColors.cyanDim, AuthColors.cyan]
                : [AuthColors.surfaceRaised, AuthColors.surfaceRaised],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AuthColors.cyan.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: enabled ? Colors.black : AuthColors.textLo,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step 1: phone with country code dropdown ─────────────────────────────────

class _PhoneStep extends StatefulWidget {
  const _PhoneStep();

  @override
  State<_PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<_PhoneStep> {
  final _controller = TextEditingController();
  String _countryCode = '+20';

  static const _codes = ['+20', '+966', '+971', '+965', '+962'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Country code — dropdown, +20 default
            Container(
              decoration: BoxDecoration(
                color: AuthColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AuthColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _countryCode,
                  dropdownColor: AuthColors.surfaceRaised,
                  iconEnabledColor: AuthColors.cyan,
                  items: [
                    for (final c in _codes)
                      DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style: const TextStyle(color: AuthColors.textHi)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _countryCode = v ?? '+20'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: AuthColors.textHi),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: _glassInput(hint: '1001234567'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
          label: t.sendVerificationCode,
          onPressed: () {
            final digits = _controller.text.trim();
            if (digits.length < 8) return;
            // Normalize: strip leading zero after country code (Egypt style)
            final normalized =
                digits.startsWith('0') ? digits.substring(1) : digits;
            context
                .read<AuthBloc>()
                .add(PhoneSubmitted('$_countryCode$normalized'));
          },
        ),
      ],
    );
  }
}

// ── Step 2: 6-digit OTP with 60s countdown ───────────────────────────────────

class _OtpStep extends StatefulWidget {
  const _OtpStep();

  @override
  State<_OtpStep> createState() => _OtpStepState();
}

class _OtpStepState extends State<_OtpStep> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthBloc>().state;
    final t = L.of(context);

    return Column(
      children: [
        // Hidden real field driving 6 visual digit boxes
        Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0,
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (v) => context.read<AuthBloc>().add(OtpChanged(v)),
              ),
            ),
            IgnorePointer(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 6; i++) ...[
                      _DigitBox(
                        digit: i < _controller.text.length
                            ? _controller.text[i]
                            : '',
                        focused: i == _controller.text.length,
                      ),
                      if (i < 5) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: state.canResend
              ? () => context.read<AuthBloc>().add(const ResendOtpRequested())
              : null,
          child: Text(
            state.canResend
                ? t.resendCode
                : t.resendCodeCountdown(state.resendCountdown),
            style: TextStyle(
              color: state.canResend ? AuthColors.cyanBright : AuthColors.textLo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({required this.digit, required this.focused});

  final String digit;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 44,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AuthColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused ? AuthColors.cyan : AuthColors.border,
          width: focused ? 1.6 : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AuthColors.cyan.withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AuthColors.cyanBright,
        ),
      ),
    );
  }
}

// ── Step 3: military ID as obscured password field ───────────────────────────

class _MilitaryIdStep extends StatefulWidget {
  const _MilitaryIdStep();

  @override
  State<_MilitaryIdStep> createState() => _MilitaryIdStepState();
}

class _MilitaryIdStepState extends State<_MilitaryIdStep> {
  final _controller = TextEditingController();
  bool _obscured = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          obscureText: _obscured,
          autofocus: true,
          enableSuggestions: false,
          autocorrect: false,
          style: const TextStyle(color: AuthColors.textHi),
          decoration: _glassInput(
            hint: t.militaryIdHint,
            prefixIcon:
                const Icon(Icons.badge_outlined, color: AuthColors.textLo),
            suffixIcon: IconButton(
              tooltip: _obscured ? t.showPassword : t.hidePassword,
              icon: Icon(
                _obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AuthColors.textLo,
              ),
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
          label: t.confirmSignIn,
          onPressed: () {
            final id = _controller.text.trim();
            if (id.length < 4) return;
            context.read<AuthBloc>().add(MilitaryIdSubmitted(id));
          },
        ),
      ],
    );
  }
}
