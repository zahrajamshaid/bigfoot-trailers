import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../domain/repositories/qc_repository.dart';
import '../viewmodel/qc_viewmodel.dart';
import '../../../shared/widgets/status_badge.dart';

/// QC Queue — shows all active QC steps grouped by QC department.
class QcQueueScreen extends StatelessWidget {
  const QcQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => QcViewModel(
        repository: ctx.read<QcRepository>(),
        ws: ctx.read<WsClient>(),
      )..load(),
      child: const _QcQueueView(),
    );
  }
}

class _QcQueueView extends StatelessWidget {
  const _QcQueueView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QcViewModel, QcState>(
      builder: (context, state) {
        if (state is QcLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is QcError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(state.message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.read<QcViewModel>().load(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (state is QcLoaded) {
          return _LoadedView(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _LoadedView extends StatelessWidget {
  final QcLoaded state;
  const _LoadedView({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.groupedQueue.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<QcViewModel>().refresh(),
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: AppColors.success),
                  SizedBox(height: 16),
                  Text('No Pending Inspections',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text('All QC queues are clear',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Sort department codes in order: QC_1, QC_2, ..., QC_5, FINAL_QC
    final sortedKeys = state.groupedQueue.keys.toList()
      ..sort((a, b) {
        const order = ['QC_1', 'QC_2', 'QC_3', 'QC_4', 'QC_5', 'FINAL_QC'];
        final ai = order.indexOf(a);
        final bi = order.indexOf(b);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    return Column(
      children: [
        // Summary header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.navy.withValues(alpha: 0.05),
          child: Row(
            children: [
              const Icon(Icons.checklist, size: 20, color: AppColors.navy),
              const SizedBox(width: 8),
              Text(
                '${state.totalCount} inspection${state.totalCount == 1 ? '' : 's'} pending',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
        // Grouped list
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => context.read<QcViewModel>().refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: sortedKeys.length,
              itemBuilder: (context, index) {
                final deptCode = sortedKeys[index];
                final items = state.groupedQueue[deptCode]!;
                return _DepartmentGroup(
                  departmentCode: deptCode,
                  departmentName: items.first.departmentName,
                  items: items,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DepartmentGroup extends StatelessWidget {
  final String departmentCode;
  final String departmentName;
  final List<QcQueueItem> items;

  const _DepartmentGroup({
    required this.departmentCode,
    required this.departmentName,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isFinalQc = departmentCode == 'FINAL_QC';
    final activeCount = items.where((e) => !e.isWaiting).length;
    final waitingCount = items.length - activeCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Department header
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isFinalQc
                      ? AppColors.amber.withValues(alpha: 0.15)
                      : AppColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFinalQc ? Icons.verified : Icons.checklist,
                      size: 16,
                      color: isFinalQc ? AppColors.amber : AppColors.navy,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$departmentCode · $departmentName',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isFinalQc ? AppColors.amber : AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$activeCount ready'
                '${waitingCount > 0 ? ' · $waitingCount upcoming' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        // Items
        ...items.map((item) => _QcQueueCard(item: item)),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _QcQueueCard extends StatelessWidget {
  final QcQueueItem item;
  const _QcQueueCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isWaiting = item.isWaiting;
    final stripColor = isWaiting
        ? Colors.grey.shade400
        : (item.isRework ? AppColors.warning : AppColors.navy);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Opacity(
        opacity: isWaiting ? 0.75 : 1.0,
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isWaiting
                ? () {
                    final stage = item.currentStageName ??
                        item.currentStageCode ??
                        'an earlier stage';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(
                          '${item.soNumber} is still at $stage. Inspect when it reaches ${item.departmentCode}.',
                        ),
                      ),
                    );
                  }
                : () => context.go('/qc/inspect/${item.stepId}', extra: item),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Left strip
                  Container(width: 5, color: stripColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // SO + stage chip + status/rework badges
                                Row(
                                  children: [
                                    Text(
                                      item.soNumber,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navy,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _StageChip(code: item.departmentCode),
                                    if (isWaiting) ...[
                                      const SizedBox(width: 6),
                                      _WaitingChip(),
                                    ],
                                    if (item.isRework) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                              color: AppColors.warning.withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.replay, size: 12,
                                                color: AppColors.warning),
                                            const SizedBox(width: 3),
                                            Text(
                                              'REWORK x${item.reworkCount}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.warning,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Model + customer
                                Text(
                                  [item.modelName, item.customerName]
                                      .where((s) => s != null && s.isNotEmpty)
                                      .join(' • '),
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey.shade600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (isWaiting && item.currentStageCode != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Currently at: ${item.currentStageName ?? item.currentStageCode}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (item.series != null)
                            SeriesBadge(series: item.series!),
                          const SizedBox(width: 8),
                          Icon(
                            isWaiting ? Icons.schedule : Icons.chevron_right,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  final String code;
  const _StageChip({required this.code});

  @override
  Widget build(BuildContext context) {
    final isFinal = code == 'FINAL_QC';
    final color = isFinal ? AppColors.amber : AppColors.navy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _WaitingChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_empty, size: 11, color: Colors.grey.shade700),
          const SizedBox(width: 3),
          Text(
            'UPCOMING',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
