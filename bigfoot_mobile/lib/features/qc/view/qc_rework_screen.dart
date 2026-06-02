import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/est_clock.dart';
import '../../../domain/repositories/qc_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/status_badge.dart';

/// Drilldown behind the dashboard "Rework Queue" tile. Lists every active
/// production step where isRework=true — trailers QC sent back to an
/// earlier department that haven't been redone yet.
class QcReworkScreen extends StatefulWidget {
  const QcReworkScreen({super.key});

  @override
  State<QcReworkScreen> createState() => _QcReworkScreenState();
}

class _QcReworkScreenState extends State<QcReworkScreen> {
  late Future<List<ReworkQueueItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ReworkQueueItem>> _load() {
    return context.read<QcRepository>().getReworkQueue();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Rework queue')),
      body: FutureBuilder<List<ReworkQueueItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final msg = snap.error is ApiException
                ? (snap.error as ApiException).displayMessage
                : snap.error.toString();
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(msg, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(l.commonRetry),
                    ),
                  ],
                ),
              ),
            );
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.task_alt,
                        size: 56, color: AppColors.success),
                    SizedBox(height: 12),
                    Text(
                      'Nothing in rework right now.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (_, i) => _ReworkRow(item: items[i]),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
            ),
          );
        },
      ),
    );
  }
}

class _ReworkRow extends StatelessWidget {
  final ReworkQueueItem item;
  const _ReworkRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final since = item.becameActiveAt != null
        ? EstClock.dateTime(item.becameActiveAt!)
        : '—';
    final dept = item.deptName ?? item.deptCode ?? '—';
    final reworkLabel = item.reworkCount > 1
        ? 'Rework attempt #${item.reworkCount}'
        : 'In rework';
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.pushNamed(
          RouteNames.trailerDetail,
          pathParameters: {'id': item.trailerId.toString()},
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          item.soNumber,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        if (item.isHot) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.local_fire_department,
                              size: 18, color: AppColors.error),
                        ],
                      ],
                    ),
                  ),
                  if (item.series != null && item.series!.isNotEmpty)
                    SeriesBadge(series: item.series!),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${item.modelName ?? '—'}'
                '${item.customerName != null ? ' • ${item.customerName}' : ''}',
                style: const TextStyle(color: AppColors.disabled),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.replay,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Back at $dept · $reworkLabel',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 13, color: AppColors.disabled),
                  const SizedBox(width: 4),
                  Text(
                    'Sent back $since',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.disabled),
                  ),
                  if (item.queuePosition != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.format_list_numbered,
                        size: 13, color: AppColors.disabled),
                    const SizedBox(width: 4),
                    Text(
                      'Queue #${item.queuePosition}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.disabled),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
