import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/iron_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/home_screen.dart';
import '../auth_repository.dart';
import '../bloc/auth_bloc.dart';

/// Phone → OTP → military ID. Each step owns the full frame; completed steps
/// collapse into a compact confirmation row so the user can see what they
/// already gave without it competing with what's being asked now.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (prev, curr) =>
          prev.status != curr.status || prev.step != curr.step,
      listener: (context, state) {
        if (state.status == AuthStatus.error) {
          HapticFeedback.heavyImpact();
        }
        if (state.status == AuthStatus.success) {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen(user: state.user!)),
            (_) => false,
          );
        }
      },
      builder: (context, state) {
        final t = L.of(context);
        return Scaffold(
          backgroundColor: IronColors.backgroundPrimary,
          appBar: AppBar(
            backgroundColor: IronColors.backgroundPrimary,
            leading: state.step == AuthStep.phone
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () =>
                        context.read<AuthBloc>().add(const StepBackRequested()),
                  ),
            title: _StepProgress(step: state.step),
            centerTitle: true,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  IronSpacing.lg, IronSpacing.xs, IronSpacing.lg, IronSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _titleFor(t, state.step),
                    style: IronTypography.displayMedium(
                        color: IronColors.textPrimary),
                  ),
                  const SizedBox(height: IronSpacing.xs),
                  Text(
                    _subtitleFor(t, state.step),
                    style: IronTypography.bodyMedium(
                        color: IronColors.textSecondary),
                  ),
                  const SizedBox(height: IronSpacing.lg),

                  if (state.step != AuthStep.phone)
                    _CompletedRow(
                      label: t.phoneNumberLabel,
                      value: state.phoneNumber,
                    ),
                  if (state.step == AuthStep.militaryId)
                    _CompletedRow(label: t.otpCodeLabel, value: '••••••'),

                  const SizedBox(height: IronSpacing.xs),

                  AnimatedSwitcher(
                    duration: IronMotion.entrance,
                    switchInCurve: IronMotion.entranceCurve,
                    switchOutCurve: IronMotion.exitCurve,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0, 0.04), end: Offset.zero)
                            .animate(anim),
                        child: child,
                      ),
                    ),
                    child: switch (state.step) {
                      AuthStep.phone => const _PhoneStep(key: ValueKey('phone')),
                      AuthStep.otp => const _OtpStep(key: ValueKey('otp')),
                      AuthStep.militaryId =>
                        const _MilitaryIdStep(key: ValueKey('id')),
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _titleFor(L t, AuthStep step) => switch (step) {
        AuthStep.phone => t.secureSignInTitle,
        AuthStep.otp => t.otpCodeLabel,
        AuthStep.militaryId => t.militaryIdHint,
      };

  static String _subtitleFor(L t, AuthStep step) => switch (step) {
        AuthStep.phone => t.phoneStepSubtitle,
        AuthStep.otp => t.otpStepSubtitle,
        AuthStep.militaryId => t.militaryIdStepSubtitle,
      };
}

/// Localized text for an auth failure. [detail] is the server's own message
/// (already in whatever language it replied in) for causes where the API
/// said something specific; everything else has copy of its own.
String authErrorText(L t, AuthErrorCode code, String? detail) => switch (code) {
      AuthErrorCode.network => t.failureOffline,
      AuthErrorCode.invalidPhone => t.errorInvalidPhone,
      AuthErrorCode.tooManyRequests => t.errorTooManyRequests,
      AuthErrorCode.invalidCode => t.errorInvalidCode,
      AuthErrorCode.sessionExpired => t.errorSessionExpired,
      AuthErrorCode.phoneVerificationFailed =>
        detail ?? t.errorPhoneVerificationFailed,
      AuthErrorCode.unexpected => detail ?? t.failureUnknown,
    };

/// Inline error beneath the field it belongs to — a message at the top of the
/// screen makes the user hunt for which input it refers to.
class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: IronSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              size: 16, color: IronColors.semanticError),
          const SizedBox(width: IronSpacing.xs),
          Expanded(
            child: Text(
              message,
              style:
                  IronTypography.bodySmall(color: IronColors.semanticError),
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress across the three steps. Announced as "step N of 3" rather than
/// rendered as decoration a screen reader would skip.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step});

  final AuthStep step;

  @override
  Widget build(BuildContext context) {
    final index = AuthStep.values.indexOf(step);
    return Semantics(
      label: 'Step ${index + 1} of ${AuthStep.values.length}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < AuthStep.values.length; i++) ...[
              AnimatedContainer(
                duration: IronMotion.entrance,
                curve: IronMotion.entranceCurve,
                width: i == index ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i <= index
                      ? IronColors.accentText
                      : IronColors.borderInteractive,
                ),
              ),
              if (i < AuthStep.values.length - 1)
                const SizedBox(width: IronSpacing.xxs),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompletedRow extends StatelessWidget {
  const _CompletedRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: IronSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: IronSpacing.md, vertical: IronSpacing.sm),
        decoration: BoxDecoration(
          color: IronColors.surfacePrimary,
          borderRadius: BorderRadius.circular(IronRadius.md),
          border: Border.all(color: IronColors.borderSubtle),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 18, color: IronColors.semanticSuccess),
            const SizedBox(width: IronSpacing.sm),
            Expanded(
              child: Text(
                label,
                style:
                    IronTypography.bodySmall(color: IronColors.textTertiary),
              ),
            ),
            Text(
              value,
              // Phone numbers stay LTR even in an RTL layout.
              textDirection: TextDirection.ltr,
              style: IronTypography.bodyMedium(color: IronColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 1: phone ─────────────────────────────────────────────────────────

class _PhoneStep extends StatefulWidget {
  const _PhoneStep({super.key});

  @override
  State<_PhoneStep> createState() => _PhoneStepState();
}

class _PhoneStepState extends State<_PhoneStep> {
  final _controller = TextEditingController();
  String _countryCode = '+20';

  static const _codes = ['+20', '+966', '+971', '+965', '+962'];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().length >= 8;

  void _submit() {
    if (!_valid) return;
    final digits = _controller.text.trim();
    final normalized = digits.startsWith('0') ? digits.substring(1) : digits;
    context.read<AuthBloc>().add(PhoneSubmitted('$_countryCode$normalized'));
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final state = context.watch<AuthBloc>().state;
    final showError =
        state.status == AuthStatus.error && state.errorCode != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: IronSpacing.sm),
              decoration: BoxDecoration(
                color: IronColors.surfacePrimary,
                borderRadius: BorderRadius.circular(IronRadius.md),
                border: Border.all(color: IronColors.borderInteractive),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _countryCode,
                  dropdownColor: IronColors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(IronRadius.md),
                  iconEnabledColor: IronColors.textSecondary,
                  style:
                      IronTypography.bodyLarge(color: IronColors.textPrimary),
                  items: [
                    for (final c in _codes)
                      DropdownMenuItem(
                        value: c,
                        child: Text(c, textDirection: TextDirection.ltr),
                      ),
                  ],
                  onChanged: (v) => setState(() => _countryCode = v ?? '+20'),
                ),
              ),
            ),
            const SizedBox(width: IronSpacing.sm),
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  style:
                      IronTypography.bodyLarge(color: IronColors.textPrimary),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  decoration: InputDecoration(
                    hintText: '1001234567',
                    errorText: showError ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ),
          ],
        ),
        if (showError)
          _FieldError(
            message: authErrorText(t, state.errorCode!, state.errorDetail),
          ),
        const SizedBox(height: IronSpacing.lg),
        IronButton(
          label: t.sendVerificationCode,
          loading: state.status == AuthStatus.loading,
          onPressed: _valid ? _submit : null,
        ),
      ],
    );
  }
}

// ── Step 2: OTP ───────────────────────────────────────────────────────────

class _OtpStep extends StatefulWidget {
  const _OtpStep({super.key});

  @override
  State<_OtpStep> createState() => _OtpStepState();
}

class _OtpStepState extends State<_OtpStep> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final state = context.watch<AuthBloc>().state;
    final showError =
        state.status == AuthStatus.error && state.errorCode != null;
    final filled = _controller.text.length;

    return Column(
      children: [
        // One real field drives six painted cells; tapping anywhere focuses it.
        Semantics(
          textField: true,
          label: t.otpCodeLabel,
          child: GestureDetector(
            onTap: () => _focus.requestFocus(),
            behavior: HitTestBehavior.opaque,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 56,
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: (v) {
                        if (v.length == 6) HapticFeedback.selectionClick();
                        context.read<AuthBloc>().add(OtpChanged(v));
                      },
                    ),
                  ),
                ),
                ExcludeSemantics(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 6; i++) ...[
                          _DigitCell(
                            digit: i < filled ? _controller.text[i] : '',
                            active: i == filled && _focus.hasFocus,
                            hasError: showError,
                          ),
                          if (i < 5) const SizedBox(width: IronSpacing.xs),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showError)
          _FieldError(
            message: authErrorText(t, state.errorCode!, state.errorDetail),
          ),
        const SizedBox(height: IronSpacing.md),
        IronButton(
          label: state.canResend
              ? t.resendCode
              : t.resendCodeCountdown(state.resendCountdown),
          variant: IronButtonVariant.ghost,
          onPressed: state.canResend
              ? () => context.read<AuthBloc>().add(const ResendOtpRequested())
              : null,
        ),
      ],
    );
  }
}

class _DigitCell extends StatelessWidget {
  const _DigitCell({
    required this.digit,
    required this.active,
    required this.hasError,
  });

  final String digit;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final border = hasError
        ? IronColors.semanticError
        : active
            ? IronColors.borderFocused
            : IronColors.borderInteractive;

    return AnimatedContainer(
      duration: IronMotion.press,
      curve: IronMotion.pressCurve,
      width: 46,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IronColors.surfacePrimary,
        borderRadius: BorderRadius.circular(IronRadius.md),
        border: Border.all(color: border, width: active || hasError ? 2 : 1),
      ),
      child: Text(
        digit,
        style: IronTypography.headlineLarge(color: IronColors.textPrimary),
      ),
    );
  }
}

// ── Step 3: military ID ───────────────────────────────────────────────────

class _MilitaryIdStep extends StatefulWidget {
  const _MilitaryIdStep({super.key});

  @override
  State<_MilitaryIdStep> createState() => _MilitaryIdStepState();
}

class _MilitaryIdStepState extends State<_MilitaryIdStep> {
  final _controller = TextEditingController();
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().length >= 4;

  void _submit() {
    if (!_valid) return;
    context
        .read<AuthBloc>()
        .add(MilitaryIdSubmitted(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final state = context.watch<AuthBloc>().state;
    final showError =
        state.status == AuthStatus.error && state.errorCode != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: TextField(
            controller: _controller,
            obscureText: _obscured,
            autofocus: true,
            enableSuggestions: false,
            autocorrect: false,
            style: IronTypography.bodyLarge(color: IronColors.textPrimary),
            decoration: InputDecoration(
              hintText: t.militaryIdHint,
              prefixIcon: const Icon(Icons.badge_outlined,
                  color: IronColors.textSecondary, size: 20),
              suffixIcon: IconButton(
                tooltip: _obscured ? t.showPassword : t.hidePassword,
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: IronColors.textSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        if (showError)
          _FieldError(
            message: authErrorText(t, state.errorCode!, state.errorDetail),
          ),
        const SizedBox(height: IronSpacing.md),
        // Reassurance at the point the most sensitive value is requested.
        Row(
          children: [
            const Icon(Icons.lock_outline,
                size: 16, color: IronColors.textTertiary),
            const SizedBox(width: IronSpacing.xs),
            Expanded(
              child: Text(
                t.e2eeNotice,
                style: IronTypography.bodySmall(color: IronColors.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: IronSpacing.lg),
        IronButton(
          label: t.confirmSignIn,
          loading: state.status == AuthStatus.loading,
          onPressed: _valid ? _submit : null,
        ),
      ],
    );
  }
}
