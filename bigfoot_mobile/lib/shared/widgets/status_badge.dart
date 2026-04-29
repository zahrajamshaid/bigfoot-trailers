import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Color-coded status chip for trailer / delivery status.
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(status);
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

  (String, Color) _resolve(String s) {
    switch (s) {
      case 'pending_production':
        return ('Pending', AppColors.statusPending);
      case 'in_production':
        return ('In Production', AppColors.statusInProduction);
      case 'ready_for_delivery':
        return ('Ready', AppColors.statusReady);
      case 'in_transit':
        return ('In Transit', AppColors.statusInTransit);
      case 'delivered':
        return ('Delivered', AppColors.statusDelivered);
      case 'on_hold':
        return ('On Hold', AppColors.statusOnHold);
      // Delivery statuses
      case 'scheduled':
        return ('Scheduled', AppColors.statusPending);
      case 'failed':
        return ('Failed', AppColors.error);
      // Step statuses
      case 'waiting':
        return ('Waiting', AppColors.statusPending);
      case 'active':
        return ('Active', AppColors.statusInProduction);
      case 'complete':
        return ('Complete', AppColors.success);
      case 'rework':
        return ('Rework', AppColors.warning);
      default:
        return (s.replaceAll('_', ' '), AppColors.disabled);
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
