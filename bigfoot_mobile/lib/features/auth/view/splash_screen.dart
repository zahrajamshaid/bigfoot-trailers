import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scale;
  Timer? _timeoutTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // ── Animations ─────────────────────────────────────────────────────────
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();

    // ── Session restore ────────────────────────────────────────────────────
    _init();

    // ── Safety timeout: 3 seconds max on splash ───────────────────────────
    _timeoutTimer = Timer(const Duration(seconds: 3), () {
      if (!_navigated && mounted) {
        _navigated = true;
        context.go('/login');
      }
    });
  }

  Future<void> _init() async {
    await context.read<AuthViewModel>().tryRestoreSession();
  }

  void _navigate(String path) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _timeoutTimer?.cancel();
    context.go(path);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthViewModel, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          _navigate('/dashboard');
        } else if (state is Unauthenticated) {
          _navigate('/login');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Stack(
          children: [
            Positioned(
              top: -80,
              left: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              right: -90,
              bottom: -70,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.amber.withValues(alpha: 0.14),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: FadeTransition(
                      opacity: _fadeIn,
                      child: ScaleTransition(
                        scale: _scale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.amber,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(height: 26),
                            Text(
                              'BIGFOOT',
                              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 6,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'TRAILERS',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppColors.amber,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 10,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Built to haul. Ready to move.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.white.withValues(alpha: 0.7),
                                    letterSpacing: 0.3,
                                  ),
                            ),
                            const SizedBox(height: 44),
                            const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                color: AppColors.amber,
                                strokeWidth: 2.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Version number at the bottom
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'v1.0.0',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white.withValues(alpha: 0.3),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
