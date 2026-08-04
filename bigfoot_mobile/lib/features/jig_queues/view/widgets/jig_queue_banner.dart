import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../model/jig_queue.dart';
import '../../viewmodel/jig_queues_cubit.dart';

/// Persistent low-jig-queue warning banner for the dashboard. Reads the
/// ambient [JigQueuesCubit]; renders nothing while a queue is healthy, and a
/// coloured, tappable warning that STAYS until the queue recovers when one is
/// low. Critical = red, warning = amber. Tapping opens the Jig Queues board.
class JigQueueBanner extends StatelessWidget {
  const JigQueueBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JigQueuesCubit, JigQueuesState>(
      builder: (context, state) {
        final board = state.board;
        if (board == null || !board.hasLow) return const SizedBox.shrink();

        final critical = board.hasCritical;
        final color = critical ? AppColors.error : AppColors.warning;
        final low = board.lowQueues;

        // "XP Jig (2), Yeti Jig (4)"
        final detail = low
            .map((JigQueue q) => '${q.displayName} (${q.count})')
            .join(', ');

        final headline = critical
            ? 'Jig queue critically low — production will stall'
            : 'Jig queue running low';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Material(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.pushNamed(RouteNames.jigQueues),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      critical ? Icons.error : Icons.warning_amber_rounded,
                      color: color,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$detail — enter more work orders to keep the line fed.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: color),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
