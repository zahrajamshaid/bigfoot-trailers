import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../dashboard/viewmodel/dashboard_viewmodel.dart';

/// Slide-out notification panel showing recent activity.
class NotificationPanel extends StatelessWidget {
  final List<ActivityItem> items;

  const NotificationPanel({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.disabled.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.notifications, color: AppColors.navy),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context).notificationPanelTitle,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const Spacer(),
                    Text(
                      '${items.length}',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.disabled,
                              ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Items
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.notifications_off_outlined,
                                size: 48, color: AppColors.disabled),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context).notificationsEmpty,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.disabled),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 56),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final (icon, color) = _iconForType(item.type);
                          return ListTile(
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: color, size: 18),
                            ),
                            title: Text(
                              item.description,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              DateFormat.jm().format(item.timestamp),
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.disabled),
                            ),
                            dense: true,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
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
      case WsEventType.trailerStalled:
        return (Icons.warning_amber_outlined, AppColors.warning);
      default:
        return (Icons.info_outline, AppColors.navy);
    }
  }
}
