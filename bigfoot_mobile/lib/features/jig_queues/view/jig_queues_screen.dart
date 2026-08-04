import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../model/jig_queue.dart';
import '../viewmodel/jig_queues_cubit.dart';

/// Dedicated "how's the line being fed" board — one card per jig with its live
/// queue depth and a colour by severity. Reached from the dashboard tile/banner.
class JigQueuesScreen extends StatelessWidget {
  const JigQueuesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<JigQueuesCubit>(
      create: (ctx) => JigQueuesCubit(api: ctx.read<DioClient>())..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Jig Queues')),
        body: BlocBuilder<JigQueuesCubit, JigQueuesState>(
          builder: (context, state) {
            final board = state.board;
            if (state.loading && board == null) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.amber),
              );
            }
            if (board == null) {
              return _ErrorView(
                message: state.error ?? 'Could not load jig queues',
                onRetry: () => context.read<JigQueuesCubit>().load(),
              );
            }

            return RefreshIndicator(
              color: AppColors.amber,
              onRefresh: () => context.read<JigQueuesCubit>().load(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _Legend(
                    warnThreshold: board.warnThreshold,
                    criticalThreshold: board.criticalThreshold,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Trailers queued at each line start (about to be welded). '
                    'When a jig runs low, get more work orders in before it stalls.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.disabled),
                  ),
                  const SizedBox(height: 12),
                  ...board.queues.map((q) => _JigCard(queue: q)),
                  if (board.queues.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: Text('No jig departments found.')),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Color _severityColor(String severity) => switch (severity) {
      'critical' => AppColors.error,
      'warning' => AppColors.warning,
      _ => AppColors.success,
    };

String _severityLabel(String severity) => switch (severity) {
      'critical' => 'CRITICAL',
      'warning' => 'LOW',
      _ => 'OK',
    };

class _JigCard extends StatelessWidget {
  final JigQueue queue;
  const _JigCard({required this.queue});

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(queue.severity);
    final noun = queue.count == 1 ? 'trailer' : 'trailers';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: queue.isLow ? 1 : 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${queue.count}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    queue.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$noun in queue',
                    style: TextStyle(fontSize: 12.5, color: AppColors.disabled),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _severityLabel(queue.severity),
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final int warnThreshold;
  final int criticalThreshold;
  const _Legend({required this.warnThreshold, required this.criticalThreshold});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _dot(AppColors.error, '≤$criticalThreshold critical'),
        _dot(AppColors.warning, '≤$warnThreshold low'),
        _dot(AppColors.success, 'healthy'),
      ],
    );
  }

  Widget _dot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.navy)),
        ],
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 40),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
