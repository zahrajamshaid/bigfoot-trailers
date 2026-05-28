import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';

/// Color-coded status chip for trailer / delivery status.
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(status, AppLocalizations.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (String, Color) _resolve(String s, AppLocalizations l) {
    switch (s) {
      case 'pending_production':
        return (l.statusPending, AppColors.statusPending);
      case 'in_production':
        return (l.statusInProduction, AppColors.statusInProduction);
      case 'ready_for_delivery':
        return (l.statusReady, AppColors.statusReady);
      case 'in_transit':
        return (l.statusInTransit, AppColors.statusInTransit);
      case 'delivered':
        return (l.statusDelivered, AppColors.statusDelivered);
      case 'on_hold':
        return (l.statusOnHold, AppColors.statusOnHold);
      // Delivery statuses
      case 'scheduled':
        return (l.statusScheduled, AppColors.statusPending);
      case 'failed':
        return (l.statusFailed, AppColors.error);
      // Step statuses
      case 'waiting':
        return (l.statusWaiting, AppColors.statusPending);
      case 'active':
        return (l.statusActive, AppColors.statusInProduction);
      case 'complete':
        return (l.statusComplete, AppColors.success);
      case 'rework':
        return (l.statusRework, AppColors.warning);
      default:
        return (s.replaceAll('_', ' '), AppColors.disabled);
    }
  }
}

/// Color-coded sale-status chip. Renders nothing for `available` since that
/// is the neutral default — only `sale_pending` and `sold` get a badge.
class SaleStatusBadge extends StatelessWidget {
  final String saleStatus;
  const SaleStatusBadge({super.key, required this.saleStatus});

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve(saleStatus, AppLocalizations.of(context));
    if (resolved == null) return const SizedBox.shrink();
    final (label, color, icon) = resolved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.white),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData)? _resolve(String s, AppLocalizations l) {
    switch (s) {
      case 'sold':
        return (l.saleStatusSold, AppColors.success, Icons.sell);
      case 'sale_pending':
        return (l.saleStatusSalePending, AppColors.warning, Icons.pending_actions);
      default:
        return null;
    }
  }
}

/// Color-coded series badge.
class SeriesBadge extends StatelessWidget {
  final String series;
  const SeriesBadge({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(series);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // Series labels are brand/product identifiers — kept as-is in both locales.
  (String, Color) _resolve(String s) {
    switch (s) {
      case 'xp':
        return ('XP', AppColors.seriesXp);
      case 'yeti':
        return ('YETI', AppColors.seriesYeti);
      case 'deck_over':
        return ('DECK OVER', AppColors.seriesDeckOver);
      case 'gooseneck_dump':
        return ('GOOSENECK', AppColors.seriesGooseneck);
      default:
        return (s.toUpperCase(), AppColors.disabled);
    }
  }
}
