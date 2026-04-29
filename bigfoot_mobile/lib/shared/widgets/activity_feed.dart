import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/websocket/ws_events.dart';
import '../../features/dashboard/viewmodel/dashboard_viewmodel.dart';

/// Recent activity feed showing the last N WebSocket events.
class ActivityFeed extends StatelessWidget {
  final List<ActivityItem> items;

  const ActivityFeed({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 40, color: AppColors.disabled),
              const SizedBox(height: 8),
              Text(
                'No recent activity',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.disabled),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'RECENT ACTIVITY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.disabled,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
          ),
        ),
        ...items.map((item) => _ActivityTile(item: item)),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final ActivityItem item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconForType(item.type);
    final timeStr = DateFormat.jm().format(item.timestamp);

    return ListTile(
      dense: true,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
      title: Text(
        item.description,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      trailing: Text(
        timeStr,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.disabled, fontSize: 11),
      ),
    );
  }

  (IconData, Color) _iconForType(String type) {
    switch (type) {
      case WsEventType.stepCompleted:
        return (Icons.check_circle_outline, AppColors.success);
      case WsEventType.qcPass:
        return (Icons.verified_outlined, AppColors.success);
      case WsEventType.qcFail:
        return (Icons.cancel_outlined, AppColors.error);
      case WsEventType.trailerReady:
        return (Icons.local_shipping_outlined, AppColors.statusReady);
      case WsEventType.deliveryDispatched:
        return (Icons.departure_board, AppColors.amber);
      case WsEventType.deliveryComplete:
        return (Icons.where_to_vote_outlined, AppColors.statusDelivered);
      case WsEventType.pointsUpdated:
        return (Icons.star_outline, AppColors.amber);
      case WsEventType.trailerStalled:
        return (Icons.warning_amber_outlined, AppColors.warning);
      default:
        return (Icons.info_outline, AppColors.navy);
    }
  }
}
