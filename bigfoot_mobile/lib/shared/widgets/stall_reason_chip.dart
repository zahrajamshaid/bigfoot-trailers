import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Compact pill that explains *why* a card is rendered red — replaces the
/// bare red stripe / red dot that used to leave workers guessing whether
/// the trailer was on fire, stalled, or both.
///
/// Pass [isHot] and the dept-derived [stallLevel] + [hoursInQueue]; the
/// widget renders nothing when neither condition fires, so callers don't
/// have to wrap it in their own conditional.
class StallReasonChip extends StatelessWidget {
  final bool isHot;
  final int stallLevel; // 0 = ok, 1 = warning, 2 = critical (red)
  final double hoursInQueue;
  /// When true, drops the icon and tightens spacing for header rows that
  /// already host other chips.
  final bool dense;

  const StallReasonChip({
    super.key,
    required this.isHot,
    required this.stallLevel,
    required this.hoursInQueue,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    // Hot is the most urgent — it always wins the red pill. A stall on top
    // of hot gets folded into the same chip as a duration suffix so workers
    // see "🔥 HOT · 4d 6h" instead of two separate badges.
    if (isHot) {
      return _Pill(
        icon: Icons.local_fire_department,
        color: AppColors.error,
        label: stallLevel >= 1
            ? 'HOT · ${_formatDuration(hoursInQueue)}'
            : 'HOT',
        dense: dense,
      );
    }
    if (stallLevel >= 2) {
      return _Pill(
        icon: Icons.schedule,
        color: AppColors.error,
        label: 'STALLED · ${_formatDuration(hoursInQueue)}',
        dense: dense,
      );
    }
    if (stallLevel == 1) {
      return _Pill(
        icon: Icons.schedule,
        color: AppColors.warning,
        label: 'SLOW · ${_formatDuration(hoursInQueue)}',
        dense: dense,
      );
    }
    return const SizedBox.shrink();
  }

  static String _formatDuration(double hours) {
    if (hours < 1) return '${(hours * 60).round()}m';
    if (hours < 24) return '${hours.toStringAsFixed(1)}h';
    final days = (hours / 24).floor();
    final remHours = (hours % 24).round();
    return remHours == 0 ? '${days}d' : '${days}d ${remHours}h';
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool dense;
  const _Pill({
    required this.icon,
    required this.color,
    required this.label,
    required this.dense,
  });
  @override
  Widget build(BuildContext context) {
    final hPad = dense ? 6.0 : 8.0;
    final vPad = dense ? 2.0 : 3.0;
    final iconSize = dense ? 11.0 : 13.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
