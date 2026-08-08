import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import 'auth_screen.dart';

/// Screen 1 — deep-navy background, gold fade-in brand, single "ابدأ" CTA.
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

  // Slow, endless breathing glow behind the logo — the "professional hover"
  // effect the badge sits in once the intro animation settles.
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
    curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
  );

  late final Animation<double> _buttonFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
  );

  late final Animation<Offset> _logoRise = Tween(
    begin: const Offset(0, 0.15),
    end: Offset.zero,
  ).animate(_logoFade);

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              SlideTransition(
                position: _logoRise,
                child: FadeTransition(
                  opacity: _logoFade,
                  child: Column(
                    children: [
                      // Brand mark — breathing glow, matches the app icon
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) => Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: IronColors.gold
                                    .withValues(alpha: 0.18 + 0.14 * _pulse.value),
                                blurRadius: 36 + 20 * _pulse.value,
                                spreadRadius: 2 + 4 * _pulse.value,
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
                          width: 140,
                          height: 140,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'IronLink',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: IronColors.gold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'منظومة التراسل المؤمَّنة',
                        style: TextStyle(
                          fontSize: 16,
                          color: IronColors.textLo,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 3),
              FadeTransition(
                opacity: _buttonFade,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 450),
                      pageBuilder: (_, anim, __) => FadeTransition(
                        opacity: anim,
                        child: const AuthScreen(),
                      ),
                    ),
                  ),
                  child: const Text('ابدأ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
