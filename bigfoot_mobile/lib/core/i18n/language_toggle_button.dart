import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'locale_cubit.dart';

/// Compact "EN" / "ES" toggle pill used in app-shell AppBars and the login
/// screen so a user can switch language without going to Settings.
class LanguageToggleButton extends StatelessWidget {
  /// Foreground color for icon + label. Pass white on dark AppBars; the login
  /// screen leaves it null so it inherits the theme's foreground.
  final Color? foregroundColor;

  const LanguageToggleButton({super.key, this.foregroundColor});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocaleCubit, Locale>(
      builder: (context, locale) {
        final code = locale.languageCode.toUpperCase();
        final fg = foregroundColor ?? Theme.of(context).iconTheme.color;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.read<LocaleCubit>().toggle(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 16, color: fg),
                    const SizedBox(width: 4),
                    Text(
                      code,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
