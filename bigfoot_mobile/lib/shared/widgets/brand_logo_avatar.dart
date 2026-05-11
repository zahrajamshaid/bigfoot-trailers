import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class BrandLogoAvatar extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry padding;

  const BrandLogoAvatar({
    super.key,
    this.size = 72,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Image.asset(
          'assets/branding/bigfoot_logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
