import 'package:flutter/material.dart';

/// A tap target that shows the click cursor on hover for mouse-driven
/// platforms (Windows/macOS/Linux desktop, web).
///
/// Material widgets like [InkWell] and [ListTile] already do this; reach for
/// [HoverTap] when the tappable surface is a raw [GestureDetector] (icons,
/// chips, logos, custom rows). It is harmless on touch platforms — with no
/// pointing device there is no cursor to change — so no platform gating is
/// needed at call sites.
///
/// When [onTap] is null the cursor falls back to the default (deferred), so a
/// disabled target doesn't falsely advertise itself as clickable.
class HoverTap extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final HitTestBehavior behavior;
  final MouseCursor cursor;

  const HoverTap({
    super.key,
    required this.onTap,
    required this.child,
    this.behavior = HitTestBehavior.opaque,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : cursor,
      child: GestureDetector(
        behavior: behavior,
        onTap: onTap,
        child: child,
      ),
    );
  }
}
