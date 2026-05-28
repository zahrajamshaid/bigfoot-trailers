import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/brand_logo_avatar.dart';

/// PIN entry screen — UI scaffold only, no real crypto.
/// Shown when user re-opens the app with "Require PIN" enabled.
class PinLockScreen extends StatefulWidget {
  final VoidCallback onSuccess;

  const PinLockScreen({super.key, required this.onSuccess});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  static const _pinLength = 4;
  String _entered = '';
  bool _error = false;

  void _onDigit(int digit) {
    if (_entered.length >= _pinLength) return;

    setState(() {
      _entered += digit.toString();
      _error = false;
    });

    if (_entered.length == _pinLength) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = false;
    });
  }

  void _verifyPin() {
    // Scaffold only — accept any 4-digit PIN for now
    // In production, compare against hashed PIN in secure storage
    HapticFeedback.lightImpact();
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 700;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: compact ? 16 : 24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      const BrandLogoAvatar(size: 64),
                      SizedBox(height: compact ? 16 : 24),

                      // Title
                      Text(
                        l.authPinTitle,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (_error)
                        Text(
                          l.authPinIncorrect,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.error,
                              ),
                        )
                      else
                        Text(
                          l.authPinSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.white.withValues(alpha: 0.6),
                              ),
                        ),

                      SizedBox(height: compact ? 20 : 32),

                      // PIN dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pinLength, (i) {
                          final filled = i < _entered.length;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            width: filled ? 18 : 16,
                            height: filled ? 18 : 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _error
                                  ? AppColors.error
                                  : filled
                                      ? AppColors.amber
                                      : AppColors.white.withValues(alpha: 0.2),
                              border: Border.all(
                                color: _error
                                    ? AppColors.error
                                    : AppColors.white.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                          );
                        }),
                      ),

                      SizedBox(height: compact ? 24 : 32),

                      // Numpad
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            for (int row = 0; row < 4; row++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: row < 3
                                      ? List.generate(3, (col) {
                                          final digit = row * 3 + col + 1;
                                          return _NumpadButton(
                                            label: '$digit',
                                            onTap: () => _onDigit(digit),
                                          );
                                        })
                                      : [
                                          const SizedBox(width: 72),
                                          _NumpadButton(
                                            label: '0',
                                            onTap: () => _onDigit(0),
                                          ),
                                          _NumpadButton(
                                            icon: Icons.backspace_outlined,
                                            onTap: _onBackspace,
                                          ),
                                        ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NumpadButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  const _NumpadButton({this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.white.withValues(alpha: 0.08),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: AppColors.white, size: 24)
            : Text(
                label ?? '',
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
              ),
      ),
    );
  }
}
