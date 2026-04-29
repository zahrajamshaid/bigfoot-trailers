import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../data/models/queue_item.dart';
import '../../../data/models/department.dart';
import '../../../domain/repositories/production_repository.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/production_viewmodel.dart';
import '../../../shared/widgets/status_badge.dart';
import 'step_completion_dialog.dart';

/// Department production queue — primary worker interface.
/// Workers see their department's queue. Managers get a department selector.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) {
        final cubit = ProductionViewModel(
          repository: ctx.read<ProductionRepository>(),
          ws: ctx.read<WsClient>(),
        );
        final authState = ctx.read<AuthViewModel>().state;
        if (authState is Authenticated) {
          final user = authState.user;
          final isManager = user.isManager;
          final deptId = user.departmentId ?? 1;
          cubit.load(deptId, isManager: isManager);
        }
        return cubit;
      },
      child: const _QueueView(),
    );
  }
}

class _QueueView extends StatelessWidget {
  const _QueueView();

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthViewModel>().state;
    final user = authState is Authenticated ? authState.user : null;
    final isManager = user?.isManager ?? false;

    return BlocConsumer<ProductionViewModel, ProductionQueueState>(
      listener: (context, state) {
        if (state is ProductionQueueLoaded && state.lastCompletion != null) {
          _showPointsNotification(context, state.lastCompletion!);
        }
      },
      builder: (context, state) {
        if (state is ProductionQueueLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ProductionQueueError) {
          return _ErrorView(
            message: state.message,
            onRetry: () {
              final deptId = user?.departmentId ?? 1;
              context.read<ProductionViewModel>().load(deptId, isManager: isManager);
            },
          );
        }
        if (state is ProductionQueueLoaded) {
          return _LoadedQueue(
            state: state,
            isManager: isManager,
          );
        }
        return const Center(child: Text('Loading queue...'));
      },
    );
  }

  void _showPointsNotification(BuildContext context, StepCompletionResult result) {
    HapticFeedback.mediumImpact();
    final points = result.pointsAwarded;
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PointsOverlay(
        points: points,
        nextDepartment: result.nextDepartment,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _LoadedQueue extends StatelessWidget {
  final ProductionQueueLoaded state;
  final bool isManager;

  const _LoadedQueue({required this.state, required this.isManager});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Manager department selector
        if (isManager && state.departments.isNotEmpty)
          _DepartmentSelector(
            departments: state.departments,
            selectedId: state.departmentId,
            onChanged: (id) =>
                context.read<ProductionViewModel>().switchDepartment(id),
          ),

        // Queue header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                state.departmentName ?? 'Queue',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${state.queue.length} trailer${state.queue.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Queue list
        Expanded(
          child: state.queue.isEmpty
              ? const _EmptyQueue()
              : RefreshIndicator(
                  onRefresh: () => context.read<ProductionViewModel>().refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: state.queue.length,
                    itemBuilder: (context, index) {
                      final item = state.queue[index];
                      return _QueueCard(
                        item: item,
                        isFirst: index == 0,
                        isManager: isManager,
                        onTap: index == 0 && !isManager
                            ? () => _showCompleteDialog(context, item)
                            : () => context.go('/trailers/${item.trailerId}'),
                        onLongPress: () => _showReverseDialog(context, item),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _showCompleteDialog(BuildContext context, QueueItem item) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<ProductionViewModel>(),
        child: StepCompletionDialog(item: item),
      ),
    );
  }

  void _showReverseDialog(BuildContext context, QueueItem item) {
    // Only allow reversal within 10 minutes of becoming active
    // (We check if item was recently completed — but since it's still in queue,
    //  this is for items the user just saw complete. Reversal is on the cubit side.)
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Undo Completion?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SO# ${item.soNumber}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              'This will return the trailer to this department\'s queue.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await context.read<ProductionViewModel>().reverseStep(item.stepId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Step reversed successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to reverse: $e')),
                  );
                }
              }
            },
            child: const Text('Undo'),
          ),
        ],
      ),
    );
  }
}

// ── Department Selector ──────────────────────────────────────────────────────

class _DepartmentSelector extends StatelessWidget {
  final List<Department> departments;
  final int selectedId;
  final ValueChanged<int> onChanged;

  const _DepartmentSelector({
    required this.departments,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Filter to non-QC production departments
    final prodDepts = departments.where((d) => !d.isQcStep).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.navy.withValues(alpha: 0.05),
      child: DropdownButtonFormField<int>(
        value: prodDepts.any((d) => d.id == selectedId) ? selectedId : null,
        decoration: InputDecoration(
          labelText: 'Department',
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: AppColors.white,
        ),
        items: prodDepts.map((d) {
          return DropdownMenuItem(
            value: d.id,
            child: Text(d.displayName, style: const TextStyle(fontSize: 14)),
          );
        }).toList(),
        onChanged: (id) {
          if (id != null) onChanged(id);
        },
      ),
    );
  }
}

// ── Queue Card ───────────────────────────────────────────────────────────────

class _QueueCard extends StatelessWidget {
  final QueueItem item;
  final bool isFirst;
  final bool isManager;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _QueueCard({
    required this.item,
    required this.isFirst,
    required this.isManager,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final stallLevel = item.stallLevel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Card(
          elevation: isFirst && !isManager ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isFirst && !isManager
                ? const BorderSide(color: AppColors.amber, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Left color strip — hot = red, stall = yellow/red, default = navy
                  Container(
                    width: 6,
                    color: item.isHot
                        ? AppColors.error
                        : stallLevel == 2
                            ? AppColors.error
                            : stallLevel == 1
                                ? AppColors.warning
                                : AppColors.navy,
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: Position + SO# + badges
                          Row(
                            children: [
                              // Queue position
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isFirst
                                      ? AppColors.amber
                                      : AppColors.navy.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '#${item.queuePosition}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isFirst ? AppColors.white : AppColors.navy,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // SO number
                              Expanded(
                                child: Text(
                                  item.soNumber,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              if (item.isHot) ...[
                                const Text('🔥', style: TextStyle(fontSize: 20)),
                                const SizedBox(width: 4),
                              ],
                              if (item.series != null)
                                SeriesBadge(series: item.series!),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Row 2: Model + customer
                          if (item.modelName != null)
                            Text(
                              item.modelName!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          if (item.customerName != null && item.customerName!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                item.customerName!,
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                            ),

                          // Row 3: Color + size
                          if (item.color != null || item.size != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  if (item.color != null)
                                    _InfoChip(label: item.color!),
                                  if (item.color != null && item.size != null)
                                    const SizedBox(width: 6),
                                  if (item.size != null)
                                    _InfoChip(label: "${item.size}ft"),
                                ],
                              ),
                            ),

                          // Row 4: Options/notes
                          if (item.optionsNotes != null && item.optionsNotes!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                item.optionsNotes!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                          // Row 5: Rework badge
                          if (item.isRework) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.replay, size: 14, color: AppColors.warning),
                                  const SizedBox(width: 4),
                                  Text(
                                    'REWORK ×${item.reworkCount}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (item.reworkFailNotes != null && item.reworkFailNotes!.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.error_outline, size: 14, color: AppColors.error),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        item.reworkFailNotes!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],

                          // Row 6: Stall indicator + time in queue
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: stallLevel == 2
                                    ? AppColors.error
                                    : stallLevel == 1
                                        ? AppColors.warning
                                        : Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              _StallText(item: item),
                              const Spacer(),
                              // Complete button for first item (worker)
                              if (isFirst && !isManager)
                                FilledButton.icon(
                                  onPressed: onTap,
                                  icon: const Icon(Icons.check_circle, size: 20),
                                  label: const Text('COMPLETE',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    minimumSize: const Size(130, 48),
                                  ),
                                ),
                            ],
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

class _StallText extends StatelessWidget {
  final QueueItem item;
  const _StallText({required this.item});

  @override
  Widget build(BuildContext context) {
    final hours = item.calculatedHoursInQueue;
    final stallLevel = item.stallLevel;
    final color = stallLevel == 2
        ? AppColors.error
        : stallLevel == 1
            ? AppColors.warning
            : Colors.grey.shade600;

    String text;
    if (hours < 1) {
      text = '${(hours * 60).round()}m in queue';
    } else if (hours < 24) {
      text = '${hours.toStringAsFixed(1)}h in queue';
    } else {
      final days = (hours / 24).floor();
      text = '${days}d ${(hours % 24).round()}h in queue';
    }

    if (stallLevel == 2) text = '⚠️ $text';

    return Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color));
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
    );
  }
}

// ── Empty Queue ──────────────────────────────────────────────────────────────

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: AppColors.success),
          SizedBox(height: 16),
          Text('Queue Empty',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text('No trailers waiting in this department',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ── Error View ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Points Overlay Animation ─────────────────────────────────────────────────

class _PointsOverlay extends StatefulWidget {
  final double points;
  final String? nextDepartment;
  final VoidCallback onDone;

  const _PointsOverlay({
    required this.points,
    this.nextDepartment,
    required this.onDone,
  });

  @override
  State<_PointsOverlay> createState() => _PointsOverlayState();
}

class _PointsOverlayState extends State<_PointsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1, end: 1), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 30),
    ]).animate(_controller);

    _offset = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0, -80),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.5, end: 1.2).chain(CurveTween(curve: Curves.elasticOut)),
          weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 60),
    ]).animate(_controller);

    _controller.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      listenable: _controller,
      builder: (_, __) {
        return Positioned(
          bottom: 120 - _offset.value.dy,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: _opacity.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.points > 0
                            ? '+${widget.points.toStringAsFixed(1)} points'
                            : 'Completed (rework)',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                      ),
                      if (widget.nextDepartment != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Next: ${widget.nextDepartment}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.white,
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
      },
    );
  }
}

/// Needed because AnimatedBuilder doesn't exist — use AnimatedWidget pattern.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) => builder(context, null);
}
