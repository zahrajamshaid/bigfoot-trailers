import 'package:flutter/material.dart';

/// Width-based form factor breakpoints (Material 3 window-size classes).
enum FormFactor { compact, medium, expanded, large }

/// Breakpoints in logical pixels.
abstract final class Breakpoints {
  static const double compact = 600;
  static const double medium = 905;
  static const double expanded = 1240;
}

/// Responsive helper read from a [BuildContext] via [context.responsive].
class Responsive {
  final Size size;
  final Orientation orientation;
  final EdgeInsets padding;
  final double textScale;

  const Responsive({
    required this.size,
    required this.orientation,
    required this.padding,
    required this.textScale,
  });

  factory Responsive.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Responsive(
      size: mq.size,
      orientation: mq.orientation,
      padding: mq.padding,
      textScale: mq.textScaler.scale(1),
    );
  }

  double get width => size.width;
  double get height => size.height;
  bool get isLandscape => orientation == Orientation.landscape;
  bool get isPortrait => orientation == Orientation.portrait;

  FormFactor get formFactor {
    if (width < Breakpoints.compact) return FormFactor.compact;
    if (width < Breakpoints.medium) return FormFactor.medium;
    if (width < Breakpoints.expanded) return FormFactor.expanded;
    return FormFactor.large;
  }

  bool get isCompact => formFactor == FormFactor.compact;
  bool get isMedium => formFactor == FormFactor.medium;
  bool get isExpanded => formFactor == FormFactor.expanded;
  bool get isLarge => formFactor == FormFactor.large;

  /// True for tablet-class widths (medium and up).
  bool get isTablet => width >= Breakpoints.compact;

  /// True for desktop-class widths.
  bool get isDesktop => width >= Breakpoints.expanded;

  /// True for very narrow phones where 2-column grids feel cramped.
  bool get isSmallPhone => width < 360;

  /// Returns the most appropriate value for the current form factor.
  T value<T>({
    required T compact,
    T? medium,
    T? expanded,
    T? large,
  }) {
    switch (formFactor) {
      case FormFactor.compact:
        return compact;
      case FormFactor.medium:
        return medium ?? compact;
      case FormFactor.expanded:
        return expanded ?? medium ?? compact;
      case FormFactor.large:
        return large ?? expanded ?? medium ?? compact;
    }
  }

  /// Column count for a stat-card / tile grid.
  int gridColumns({
    int compact = 2,
    int medium = 3,
    int expanded = 4,
    int large = 5,
  }) {
    if (isSmallPhone && compact > 1) return 1;
    return value(
      compact: compact,
      medium: medium,
      expanded: expanded,
      large: large,
    );
  }

  /// Standard horizontal page padding.
  double get pagePadding =>
      value(compact: 12, medium: 20, expanded: 32, large: 48);

  /// Horizontal padding for content centred at a max width on wide screens.
  EdgeInsets get pageInsets => EdgeInsets.symmetric(horizontal: pagePadding);

  /// Max content width for forms / lists on tablet+ — prevents overstretched UI.
  double get maxContentWidth =>
      value(compact: double.infinity, medium: 720, expanded: 880, large: 1040);

  /// Aspect ratio for stat-card grids — slightly taller on small phones.
  double get statCardAspectRatio =>
      isSmallPhone ? 1.6 : value(compact: 1.35, medium: 1.45, expanded: 1.55);
}

extension ResponsiveContext on BuildContext {
  Responsive get responsive => Responsive.of(this);
  bool get isTablet => Responsive.of(this).isTablet;
  bool get isCompact => Responsive.of(this).isCompact;
}

/// Constrains its child to a centred max-width on wide screens.
class ResponsiveContent extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;

  const ResponsiveContent({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final effectiveMax = maxWidth ?? r.maxContentWidth;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMax),
        child: Padding(
          padding: padding ?? r.pageInsets,
          child: child,
        ),
      ),
    );
  }
}
