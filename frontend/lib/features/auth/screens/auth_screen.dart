import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme.dart';
import '../../home/home_screen.dart';
import '../bloc/auth_bloc.dart';

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
        if (state.status == AuthStatus.error && state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.gpp_bad_outlined, color: IronColors.textHi),
                  const SizedBox(width: 12),
                  Expanded(child: Text(state.errorMessage!)),
                ],
              ),
            ));
        }
        if (state.status == AuthStatus.success) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => HomeScreen(user: state.user!)),
            (_) => false,
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Icon(Icons.shield_outlined,
                      size: 40, color: IronColors.gold),
                  const SizedBox(height: 16),
                  const Text(
                    'تسجيل الدخول الآمن',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitleFor(state.step),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: IronColors.textLo),
                  ),
                  const SizedBox(height: 32),

                  // Step 1 — phone
                  _StepContainer(
                    active: state.step == AuthStep.phone,
                    done: state.step != AuthStep.phone,
                    doneSummary: state.phoneNumber,
                    child: const _PhoneStep(),
                  ),

                  // Step 2 — OTP
                  _StepContainer(
                    active: state.step == AuthStep.otp,
                    done: state.step == AuthStep.militaryId,
                    doneSummary: '••••••',
                    child: const _OtpStep(),
                  ),

                  // Step 3 — military ID
                  _StepContainer(
                    active: state.step == AuthStep.militaryId,
                    done: false,
                    doneSummary: '',
                    child: const _MilitaryIdStep(),
                  ),

                  if (state.status == AuthStatus.loading) ...[
                    const SizedBox(height: 24),
                    const Center(
                      child: CircularProgressIndicator(
                          color: IronColors.gold),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _subtitleFor(AuthStep step) => switch (step) {
        AuthStep.phone => 'أدخل رقم هاتفك المسجل لدى الوحدة',
        AuthStep.otp => 'أدخل رمز التحقق المرسل إليك',
        AuthStep.militaryId => 'أدخل رقمك العسكري لإتمام التحقق',
      };
}

/// Wraps a step: animates in when active, collapses to a summary chip when done.
class _StepContainer extends StatelessWidget {
  const _StepContainer({
    required this.active,
    required this.done,
    required this.doneSummary,
    required this.child,
  });

  final bool active;
  final bool done;
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
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: IronColors.navySurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: IronColors.navyBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: IronColors.success, size: 20),
                        const SizedBox(width: 10),
                        Text(doneSummary,
                            style:
                                const TextStyle(color: IronColors.textLo)),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Country code — dropdown, +20 default
            Container(
              decoration: BoxDecoration(
                color: IronColors.navySurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: IronColors.navyBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _countryCode,
                  dropdownColor: IronColors.navySurface,
                  items: [
                    for (final c in _codes)
                      DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style:
                                const TextStyle(color: IronColors.textHi)),
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
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration:
                    const InputDecoration(hintText: '1001234567'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            final digits = _controller.text.trim();
            if (digits.length < 8) return;
            // Normalize: strip leading zero after country code (Egypt style)
            final normalized = digits.startsWith('0')
                ? digits.substring(1)
                : digits;
            context
                .read<AuthBloc>()
                .add(PhoneSubmitted('$_countryCode$normalized'));
          },
          child: const Text('إرسال رمز التحقق'),
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
                onChanged: (v) =>
                    context.read<AuthBloc>().add(OtpChanged(v)),
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
                      if (i < 5) const SizedBox(width: 10),
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
              ? () =>
                  context.read<AuthBloc>().add(const ResendOtpRequested())
              : null,
          child: Text(
            state.canResend
                ? 'إعادة إرسال الرمز'
                : 'إعادة الإرسال بعد ${state.resendCountdown} ثانية',
            style: TextStyle(
              color:
                  state.canResend ? IronColors.gold : IronColors.textLo,
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
      width: 46,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IronColors.navySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused ? IronColors.gold : IronColors.navyBorder,
          width: focused ? 1.6 : 1,
        ),
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: IronColors.goldBright,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          obscureText: _obscured,
          autofocus: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'الرقم العسكري',
            prefixIcon:
                const Icon(Icons.badge_outlined, color: IronColors.textLo),
            suffixIcon: IconButton(
              tooltip: _obscured ? 'إظهار' : 'إخفاء',
              icon: Icon(
                _obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: IronColors.textLo,
              ),
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            final id = _controller.text.trim();
            if (id.length < 4) return;
            context.read<AuthBloc>().add(MilitaryIdSubmitted(id));
          },
          child: const Text('تأكيد الدخول'),
        ),
      ],
    );
  }
}
