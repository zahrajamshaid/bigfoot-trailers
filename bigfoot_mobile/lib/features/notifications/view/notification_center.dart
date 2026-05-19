import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/app_notification.dart';
import '../viewmodel/notifications_viewmodel.dart';

class NotificationCenter extends StatefulWidget {
  const NotificationCenter({super.key});

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  @override
  void initState() {
    super.initState();
    context.read<NotificationsViewModel>().loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Center'),
        actions: [
          TextButton(
            onPressed: () => context.read<NotificationsViewModel>().markAllRead(),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: BlocBuilder<NotificationsViewModel, NotificationsState>(
        builder: (context, state) {
          if (state.items.isEmpty) {
            return const Center(child: Text('No notifications yet'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: state.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final n = state.items[i];
              final (icon, color) = _iconForType(n.type);

              return Slidable(
                key: ValueKey(n.id),
                endActionPane: ActionPane(
                  motion: const StretchMotion(),
                  children: [
                    SlidableAction(
                      onPressed: (_) => context.read<NotificationsViewModel>().dismiss(n.id),
                      backgroundColor: AppColors.error,
                      icon: Icons.delete_outline,
                      label: 'Delete',
                    ),
                  ],
                ),
                child: ListTile(
                  onTap: () => _onTap(n),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: n.isRead ? AppColors.divider : AppColors.amber,
                    ),
                  ),
                  tileColor: AppColors.white,
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.14),
                    child: Icon(icon, color: color),
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                  subtitle: Text('${n.body}\n${DateFormat.yMd().add_jm().format(n.timestamp)}'),
                  isThreeLine: true,
                  trailing: n.isRead
                      ? null
                      : const Icon(Icons.fiber_manual_record,
                          size: 10, color: AppColors.amber),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _onTap(AppNotification n) async {
    context.read<NotificationsViewModel>().markRead(n.id);

    final payload = n.payload ?? const <String, dynamic>{};
    final trailerId = payload['trailerId']?.toString() ?? payload['trailer_id']?.toString();
    final deliveryId = payload['deliveryId']?.toString() ?? payload['delivery_id']?.toString();

    switch (n.type) {
      case NotificationType.workerMessage:
        if (trailerId != null) {
          context.pushNamed(
            RouteNames.workerMessages,
            pathParameters: {'trailerId': trailerId},
          );
          return;
        }
        return;
      case NotificationType.deliveryDispatched:
      case NotificationType.deliveryComplete:
      case NotificationType.paymentNotCollected:
        if (deliveryId != null) {
          context.pushNamed(
            RouteNames.deliveryDetail,
            pathParameters: {'id': deliveryId},
          );
          return;
        }
        return;
      default:
        if (trailerId != null) {
          context.pushNamed(
            RouteNames.trailerDetail,
            pathParameters: {'id': trailerId},
          );
          return;
        }
        return;
    }
  }

  (IconData, Color) _iconForType(String type) {
    switch (type) {
      case NotificationType.qcFail:
        return (Icons.cancel_outlined, AppColors.error);
      case NotificationType.paymentNotCollected:
        return (Icons.money_off_csred_outlined, AppColors.warning);
      case NotificationType.trailerStalled:
        return (Icons.warning_amber_rounded, AppColors.warning);
      case NotificationType.deliveryDispatched:
        return (Icons.departure_board_outlined, AppColors.statusInTransit);
      case NotificationType.deliveryComplete:
        return (Icons.check_circle_outline, AppColors.statusDelivered);
      case NotificationType.workerMessage:
        return (Icons.message_outlined, AppColors.navy);
      default:
        return (Icons.notifications_outlined, AppColors.navy);
    }
  }
}
