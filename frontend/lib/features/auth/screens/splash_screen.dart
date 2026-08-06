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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

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
                      // Gold laurel shield mark
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: MilColors.gold, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: MilColors.gold.withValues(alpha: 0.25),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          size: 56,
                          color: MilColors.gold,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'IronLink',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: MilColors.gold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'منظومة التراسل المؤمَّنة',
                        style: TextStyle(
                          fontSize: 16,
                          color: MilColors.textLo,
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
