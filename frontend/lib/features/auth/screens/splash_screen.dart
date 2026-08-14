import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/home_screen.dart';
import '../auth_repository.dart';
import 'auth_colors.dart';
import 'auth_screen.dart';

/// Screen 1 — welcome/intro. Shares AuthColors with the rest of the auth
/// flow (phone/OTP/military ID) so all four screens read as one system;
/// the rest of the app (chat, home, settings...) is untouched until it's
/// redesigned too.
typedef _WelcomeColors = AuthColors;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

  // Slow, endless breathing glow behind the logo.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = CurvedAnimation(
    parent: _pulseController,
    curve: Curves.easeInOut,
  );

  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
  );

  late final Animation<double> _bodyFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 0.8, curve: Curves.easeOut),
  );

  late final Animation<double> _buttonFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
  );

  late final Animation<Offset> _logoRise = Tween(
    begin: const Offset(0, 0.15),
    end: Offset.zero,
  ).animate(_logoFade);

  List<(IconData, String)> _features(L t) => [
        (Icons.lock_outline, t.featureE2EE),
        (Icons.verified_user_outlined, t.featureVerifiedIdentity),
        (Icons.visibility_off_outlined, t.featurePrivacyByDesign),
        (Icons.phonelink_lock_outlined, t.featureDeviceSecurity),
      ];

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _goToAuth() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: const AuthScreen(),
        ),
      ),
    );
  }

  /// Debug-only shortcut: skips Firebase Phone Auth and the backend token
  /// exchange entirely, landing straight on Home with a locally-built user.
  /// Lets UI/feature work continue while Render/Firebase are being wired up
  /// — never compiled into a release build (guarded by kDebugMode above).
  void _enterAsGuest(BuildContext context) {
    const guest = AuthUser(
      id: 'dev-guest',
      fullName: 'ضيف تجريبي',
      username: 'dev_guest',
      role: 'member',
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(user: guest)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return Scaffold(
      backgroundColor: _WelcomeColors.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.1,
            colors: [_WelcomeColors.bgVignette, _WelcomeColors.bg],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                SlideTransition(
                  position: _logoRise,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, child) => Container(
                            width: 132,
                            height: 132,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _WelcomeColors.cyan.withValues(
                                      alpha: 0.22 + 0.16 * _pulse.value),
                                  blurRadius: 40 + 22 * _pulse.value,
                                  spreadRadius: 2 + 5 * _pulse.value,
                                ),
                              ],
                            ),
                            child: Transform.scale(
                              scale: 1.0 + 0.03 * _pulse.value,
                              child: child,
                            ),
                          ),
                          child: Image.asset(
                            'assets/icons/logo_mark.png',
                            width: 132,
                            height: 132,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'IRONLINK',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: _WelcomeColors.textHi,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.authTagline,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _WelcomeColors.cyan,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                FadeTransition(
                  opacity: _bodyFade,
                  child: Column(
                    children: [
                      Text(
                        t.authSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: _WelcomeColors.textLo,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final f in _features(t))
                            Expanded(child: _FeatureBadge(icon: f.$1, label: f.$2)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: _buttonFade,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 54,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [
                                _WelcomeColors.cyanDim,
                                _WelcomeColors.cyan,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _WelcomeColors.cyan.withValues(alpha: 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _goToAuth,
                              child: Center(
                                child: Text(
                                  t.getStarted,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: _goToAuth,
                        style: TextButton.styleFrom(
                          foregroundColor: _WelcomeColors.textLo,
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14, color: _WelcomeColors.textLo),
                            children: [
                              TextSpan(text: t.alreadyHaveAccount),
                              TextSpan(
                                text: t.signIn,
                                style: const TextStyle(
                                  color: _WelcomeColors.cyanBright,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (kDebugMode) ...[
                        const SizedBox(height: 10),
                        _DevGuestButton(
                          label: t.devGuestLogin,
                          onTap: () => _enterAsGuest(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Visually distinct from every real auth action — dashed amber outline and
/// an explicit "DEV" tag — so nobody mistakes it for a real login path.
class _DevGuestButton extends StatelessWidget {
  const _DevGuestButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  static const _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _amber.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'DEV',
                  style: TextStyle(
                    color: _amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: _amber, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _WelcomeColors.fill,
              border: Border.all(color: _WelcomeColors.border),
            ),
            child: Icon(icon, size: 20, color: _WelcomeColors.cyan),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 10.5,
              color: _WelcomeColors.textLo,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
