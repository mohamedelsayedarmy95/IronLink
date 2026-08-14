import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/iron_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/home_screen.dart';
import '../auth_repository.dart';
import 'auth_screen.dart';

/// Welcome screen. Restraint is the point: one mark, one promise, one action.
/// The previous pass leaned on a pulsing cyan halo and four feature badges,
/// which read as a product arguing for itself rather than one that's sure.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final Animation<double> _markFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.6, curve: IronMotion.entranceCurve),
  );

  late final Animation<double> _copyFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.25, 0.8, curve: IronMotion.entranceCurve),
  );

  late final Animation<double> _actionFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 1.0, curve: IronMotion.entranceCurve),
  );

  late final Animation<Offset> _markRise = Tween(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(_markFade);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Users who ask for reduced motion get the final frame, not a fade.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToAuth() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: IronMotion.page,
        reverseTransitionDuration: IronMotion.exit,
        pageBuilder: (_, __, ___) => const AuthScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: IronMotion.pageCurve),
          child: child,
        ),
      ),
    );
  }

  /// Debug-only: skips Firebase and the backend exchange entirely so UI work
  /// can continue while server config is still being wired up. Never compiled
  /// into a release build.
  void _enterAsGuest() {
    const guest = AuthUser(
      id: 'dev-guest',
      fullName: 'Dev Guest',
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
      backgroundColor: IronColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: IronSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              SlideTransition(
                position: _markRise,
                child: FadeTransition(
                  opacity: _markFade,
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/icons/logo_mark.png',
                        width: 104,
                        height: 104,
                        fit: BoxFit.contain,
                        // Brand mark; the wordmark beneath already names it.
                        excludeFromSemantics: true,
                      ),
                      const SizedBox(height: IronSpacing.lg),
                      Text(
                        'IRONLINK',
                        textAlign: TextAlign.center,
                        style: IronTypography.displayLarge(
                          color: IronColors.textPrimary,
                        ).copyWith(letterSpacing: 6),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: IronSpacing.sm),
              FadeTransition(
                opacity: _copyFade,
                child: Text(
                  t.authTagline,
                  textAlign: TextAlign.center,
                  style:
                      IronTypography.bodyMedium(color: IronColors.textSecondary),
                ),
              ),
              const Spacer(flex: 2),
              FadeTransition(
                opacity: _copyFade,
                child: Text(
                  t.authSubtitle,
                  textAlign: TextAlign.center,
                  style: IronTypography.headlineMedium(
                      color: IronColors.textPrimary),
                ),
              ),
              const Spacer(flex: 3),
              FadeTransition(
                opacity: _actionFade,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IronButton(label: t.getStarted, onPressed: _goToAuth),
                    const SizedBox(height: IronSpacing.xs),
                    IronButton(
                      label: t.signIn,
                      variant: IronButtonVariant.ghost,
                      onPressed: _goToAuth,
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: IronSpacing.xs),
                      const _DevBadgeDivider(),
                      const SizedBox(height: IronSpacing.xs),
                      IronButton(
                        label: t.devGuestLogin,
                        variant: IronButtonVariant.secondary,
                        onPressed: _enterAsGuest,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: IronSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marks the debug-only affordance below it as not part of the product, so a
/// screenshot of a debug build can't be mistaken for a real sign-in path.
class _DevBadgeDivider extends StatelessWidget {
  const _DevBadgeDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: IronColors.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IronSpacing.sm),
          child: Text(
            'DEBUG BUILD',
            style: IronTypography.labelSmall(color: IronColors.semanticWarning),
          ),
        ),
        const Expanded(child: Divider(color: IronColors.borderSubtle)),
      ],
    );
  }
}
