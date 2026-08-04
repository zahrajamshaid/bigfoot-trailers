import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/user.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../data/support_api.dart';
import '../model/support_ticket.dart';
import '../viewmodel/support_list_cubit.dart';

/// Ticket inbox. Admins (owner/office/PM) see every report; everyone else sees
/// only their own. Title adapts accordingly.
class SupportListScreen extends StatelessWidget {
  const SupportListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthViewModel>().state;
    final role = auth is Authenticated ? auth.user.role : null;
    final adminView = role == UserRole.owner ||
        role == UserRole.office ||
        role == UserRole.productionManager;
    return BlocProvider<SupportListCubit>(
      create: (ctx) => SupportListCubit(SupportApi(ctx.read<DioClient>()))..load(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(adminView ? 'Problem reports' : 'My reports'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await context.pushNamed(RouteNames.supportReport);
            if (context.mounted) context.read<SupportListCubit>().load();
          },
          backgroundColor: AppColors.amber,
          icon: const Icon(Icons.add),
          label: const Text('Report'),
        ),
        body: BlocBuilder<SupportListCubit, SupportListState>(
          builder: (context, state) {
            if (state.loading && state.tickets.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.amber),
              );
            }
            if (state.error != null && state.tickets.isEmpty) {
              return _Retry(
                message: 'Could not load reports',
                onRetry: () => context.read<SupportListCubit>().load(),
              );
            }
            if (state.tickets.isEmpty) {
              return _Empty(adminView: adminView);
            }
            return RefreshIndicator(
              color: AppColors.amber,
              onRefresh: () => context.read<SupportListCubit>().load(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: state.tickets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = state.tickets[i];
                  final card = _TicketCard(
                    ticket: t,
                    showReporter: adminView,
                    onTap: () async {
                      await context.pushNamed(
                        RouteNames.supportThread,
                        pathParameters: {'id': '${t.id}'},
                      );
                      if (context.mounted) {
                        context.read<SupportListCubit>().load();
                      }
                    },
                  );
                  // Admins can swipe a report away to clear stale/test threads.
                  if (!adminView) return card;
                  return Dismissible(
                    key: ValueKey('ticket-${t.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete, color: AppColors.white),
                    ),
                    confirmDismiss: (_) async {
                      final api = SupportApi(context.read<DioClient>());
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete this report?'),
                          content: const Text('Removes the whole conversation. Can\'t be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return false;
                      try {
                        await api.deleteTicket(t.id);
                        return true;
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
                        );
                        return false;
                      }
                    },
                    onDismissed: (_) => context.read<SupportListCubit>().load(),
                    child: card,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final SupportTicketSummary ticket;
  final bool showReporter;
  final VoidCallback onTap;
  const _TicketCard({
    required this.ticket,
    required this.showReporter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final open = ticket.isOpen;
    final statusColor = open ? AppColors.warning : AppColors.success;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          ticket.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showReporter)
              Text('From ${ticket.reporterName}',
                  style: TextStyle(fontSize: 12, color: AppColors.disabled)),
            if (ticket.lastPreview != null)
              Text(
                ticket.lastPreview!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                open ? 'OPEN' : 'RESOLVED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('${ticket.messageCount} msg',
                style: TextStyle(fontSize: 11, color: AppColors.disabled)),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool adminView;
  const _Empty({required this.adminView});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(Icons.inbox_outlined, size: 48, color: AppColors.disabled),
        const SizedBox(height: 12),
        Center(
          child: Text(
            adminView ? 'No problem reports yet.' : 'You haven\'t reported anything.',
            style: TextStyle(color: AppColors.disabled),
          ),
        ),
      ],
    );
  }
}

class _Retry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Retry({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
