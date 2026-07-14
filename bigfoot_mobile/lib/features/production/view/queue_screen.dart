import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/queue_item.dart';
import '../../../data/models/department.dart';
import '../../../domain/repositories/trailer_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/production_viewmodel.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ownership_chip.dart';
import '../../../shared/widgets/stall_reason_chip.dart';
import 'step_completion_dialog.dart';

/// Department production queue — primary worker interface.
/// Workers see their department's queue. Managers get a department selector.
class QueueScreen extends StatefulWidget {
  /// When true the queue opens with the "Stalled only" filter applied —
  /// used by the dashboard "Stalled Steps" deep link (`?filter=stalled`).
  final bool initialStalledOnly;

  const QueueScreen({super.key, this.initialStalledOnly = false});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  @override
  void initState() {
    super.initState();
    // The cubit is provided at app level so its filter state outlives any
    // re-mount of this screen (tap a card -> root nav push -> back). We only
    // trigger an initial load when there's no data yet, or when the screen
    // was opened from a deep link that wants to force a specific filter.
    // Without this guard a back-nav re-instantiation would smash the user's
    // chip / search selections every time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = context.read<ProductionViewModel>();
      final state = cubit.state;
      final hasDeepLink = widget.initialStalledOnly;
      final alreadyLoaded = state is ProductionQueueLoaded;
      if (alreadyLoaded && !hasDeepLink) return;

      final authState = context.read<AuthViewModel>().state;
      if (authState is! Authenticated) return;
      final user = authState.user;
      // Production-admin tier (owner / office / production_manager /
      // qc_inspector) gets the multi-dept fetch path: every department's
      // queue is loaded and a selector lets them switch between any of
      // them. Workers still get just their own primary + extras. Without
      // this, QC fell into the worker branch and hit "no department is
      // assigned to this account" because qc_inspector accounts have no
      // primary production department.
      cubit.load(
        user.departmentId,
        isManager: user.isProductionAdmin,
        allowedDepartmentIds: user.allDepartmentIds,
        stalledOnly: widget.initialStalledOnly,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const _QueueView();
}

class _QueueView extends StatelessWidget {
  const _QueueView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final authState = context.watch<AuthViewModel>().state;
    final user = authState is Authenticated ? authState.user : null;
    // QC inspectors get the same production-floor UI as production_manager
    // (tap-card-to-detail, no "Complete step" button on each row, queue
    // reorder permission). The User.isProductionAdmin getter covers
    // owner + office + production_manager + qc_inspector.
    final isManager = user?.isProductionAdmin ?? false;

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
              final deptId = user?.departmentId;
              context.read<ProductionViewModel>().load(
                deptId,
                isManager: isManager,
                allowedDepartmentIds: user?.allDepartmentIds ?? const <int>[],
              );
            },
          );
        }
        if (state is ProductionQueueLoaded) {
          return _LoadedQueue(state: state, isManager: isManager);
        }
        return Center(child: Text(l.queueLoading));
      },
    );
  }

  void _showPointsNotification(
    BuildContext context,
    StepCompletionResult result,
  ) {
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
    final l = AppLocalizations.of(context);
    final visibleQueue = state.visibleQueue;
    final stalledCount = state.queue.where((q) => q.stallLevel > 0).length;

    return Column(
      children: [
        // Department selector — shown for managers (all depts) and for
        // "master" worker accounts whose extraDepartmentIds give them more
        // than one queue to choose from. Hidden for single-dept workers.
        if (state.departments.length > 1)
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
                state.departmentName ?? l.queueTitleFallback,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const Spacer(),
              // Stalled-only filter — shows only items past the stall
              // threshold. Always visible so a deep-linked filter can be
              // cleared even when it leaves the list empty.
              FilterChip(
                label: Text(stalledCount > 0
                    ? l.queueFilterStalledCount(stalledCount)
                    : l.queueFilterStalled),
                avatar: const Icon(Icons.warning_amber, size: 16),
                selected: state.stalledOnly,
                selectedColor: AppColors.warning.withValues(alpha: 0.2),
                visualDensity: VisualDensity.compact,
                onSelected: (v) =>
                    context.read<ProductionViewModel>().setStalledOnly(v),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l.queueTrailerCount(visibleQueue.length),
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
          child: visibleQueue.isEmpty
              ? (state.stalledOnly ? const _NoStalledItems() : const _EmptyQueue())
              : RefreshIndicator(
                  onRefresh: () =>
                      context.read<ProductionViewModel>().refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: visibleQueue.length,
                    itemBuilder: (context, index) {
                      final item = visibleQueue[index];
                      return _QueueCard(
                        item: item,
                        isFirst: index == 0,
                        isManager: isManager,
                        // Workers: tap anywhere on the card to complete it,
                        // regardless of position. Managers continue to drill
                        // through to the trailer detail.
                        onTap: isManager
                            ? () => context.push('/trailers/${item.trailerId}')
                            : () => _showCompleteDialog(context, item),
                        // A small info button is exposed for workers who
                        // still need to open the trailer detail.
                        onOpenDetail: () =>
                            context.push('/trailers/${item.trailerId}'),
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
    final productionViewModel = context.read<ProductionViewModel>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: productionViewModel,
        child: StepCompletionDialog(item: item, parentContext: context),
      ),
    );
  }

  void _showReverseDialog(BuildContext context, QueueItem item) {
    final l = AppLocalizations.of(context);
    // Capture everything that needs a context off the *queue screen's*
    // context before the dialog opens. The dialog's own builder context is
    // disposed the moment Navigator.pop fires — calling context.read or
    // ScaffoldMessenger.of on it after pop throws "Looking up a
    // deactivated widget's ancestor is unsafe", which used to crash the
    // app the instant the user tapped Undo.
    final cubit = context.read<ProductionViewModel>();
    final trailerRepo = context.read<TrailerRepository>();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.queueUndoTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SO# ${item.soNumber}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              l.queueUndoBody,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                // Queue items always reference the trailer's *active* step,
                // but POST /production/steps/:id/reverse only operates on
                // completed steps (the active one has nothing to roll back
                // to). To send the trailer "back to its previous
                // department" we need to find the most recently completed
                // step on the same trailer and reverse THAT — the prior
                // step becomes active again and the current active drops
                // back to waiting.
                final steps = await trailerRepo.getSteps(item.trailerId);
                final completed = steps
                    .where((s) => s.status == 'complete')
                    .toList()
                  ..sort((a, b) => b.stepOrder.compareTo(a.stepOrder));
                if (completed.isEmpty) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Nothing to undo — this trailer has not '
                        'completed a step yet.',
                      ),
                    ),
                  );
                  return;
                }
                await cubit.reverseStep(completed.first.id);
                messenger.showSnackBar(
                  SnackBar(content: Text(l.queueReversed)),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l.queueReverseFailed('$e'))),
                );
              }
            },
            child: Text(l.commonUndo),
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
    final l = AppLocalizations.of(context);
    // Filter to non-QC production departments
    final prodDepts = departments.where((d) => !d.isQcStep).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.navy.withValues(alpha: 0.05),
      child: DropdownButtonFormField<int>(
        value: prodDepts.any((d) => d.id == selectedId) ? selectedId : null,
        decoration: InputDecoration(
          labelText: l.queueDepartmentLabel,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
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
  final VoidCallback onOpenDetail;
  final VoidCallback onLongPress;

  const _QueueCard({
    required this.item,
    required this.isFirst,
    required this.isManager,
    required this.onTap,
    required this.onOpenDetail,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final stallLevel = item.stallLevel;

    // Long-press lives on the InkWell, not on an outer GestureDetector,
    // because Material's InkWell claims the press-down gesture as soon as
    // the user touches the card to draw the ripple. With the press claimed,
    // a sibling GestureDetector's onLongPress timer never fires (Flutter's
    // gesture arena resolves to the InkWell). Wiring onLongPress directly
    // into the InkWell hands it both the tap and the long-press cleanly.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
          onLongPress: onLongPress,
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
                          // Row 1: SO# + series badge + ownership + reason
                          //
                          // The internal `#queuePosition` circle was
                          // dropped — workers don't act on the numeric
                          // index, only on "is this my next one to grab"
                          // which is already conveyed by the amber border
                          // on the first card. The badges that DO matter
                          // (ownership + stall reason) get the freed space.
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                item.soNumber,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              if (item.series != null)
                                SeriesBadge(series: item.series!),
                              OwnershipChip(
                                isCustomerOrder: item.isCustomerOrder,
                                buyerName: item.buyerName,
                              ),
                              if (item.isHot || stallLevel >= 1)
                                StallReasonChip(
                                  isHot: item.isHot,
                                  stallLevel: stallLevel,
                                  hoursInQueue:
                                      item.calculatedHoursInQueue,
                                ),
                              // Options THIS department has to fit. Blocks step
                              // completion until acknowledged, so flag it on the
                              // card — the worker shouldn't have to open the
                              // trailer to find out.
                              if (item.optionsToFit > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.error,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.build_circle_outlined,
                                          size: 13, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(
                                        item.optionsToFit == 1
                                            ? '1 OPTION TO FIT'
                                            : '${item.optionsToFit} OPTIONS TO FIT',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Row 2: Model name
                          if (item.modelName != null)
                            Text(
                              item.modelName!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
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
                          if (item.optionsNotes != null &&
                              item.optionsNotes!.isNotEmpty)
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.warning.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.replay,
                                    size: 14,
                                    color: AppColors.warning,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    l.queueReworkBadge(item.reworkCount),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (item.reworkFailNotes != null &&
                                item.reworkFailNotes!.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.error.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 14,
                                      color: AppColors.error,
                                    ),
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

                          // Row 6: Stall indicator + time in queue + actions
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
                              // Workers can complete any trailer in their
                              // queue, not just the top one. Info icon
                              // remains available as an escape hatch into
                              // the trailer detail screen.
                              if (!isManager) ...[
                                IconButton(
                                  onPressed: onOpenDetail,
                                  icon: const Icon(
                                    Icons.info_outline,
                                    color: AppColors.navy,
                                  ),
                                  tooltip: l.queueOpenDetailTooltip,
                                  visualDensity: VisualDensity.compact,
                                ),
                                FilledButton.icon(
                                  onPressed: onTap,
                                  icon: const Icon(
                                    Icons.check_circle,
                                    size: 20,
                                  ),
                                  label: Text(
                                    l.queueCompleteButton,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    minimumSize: const Size(130, 48),
                                  ),
                                ),
                              ],
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
      );
  }
}

class _StallText extends StatelessWidget {
  final QueueItem item;
  const _StallText({required this.item});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hours = item.calculatedHoursInQueue;
    final stallLevel = item.stallLevel;
    final color = stallLevel == 2
        ? AppColors.error
        : stallLevel == 1
        ? AppColors.warning
        : Colors.grey.shade600;

    String text;
    if (hours < 1) {
      text = l.queueMinutesInQueue((hours * 60).round());
    } else if (hours < 24) {
      text = l.queueHoursInQueue(hours.toStringAsFixed(1));
    } else {
      final days = (hours / 24).floor();
      text = l.queueDaysHoursInQueue(days, (hours % 24).round());
    }

    // Stalled / hot trailers are already loud-called-out by StallReasonChip
    // at the top of the card, so this bottom row stays as a quiet time-in-
    // queue readout. Earlier this prepended a ⚠️ glyph that doubled up
    // alongside the clock icon next to it and read as "stall symbol stacked
    // on the clock symbol".

    return Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    );
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
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
    );
  }
}

// ── Empty Queue ──────────────────────────────────────────────────────────────

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 64, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            l.queueEmptyTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            l.queueEmptyBody,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

/// Shown when the "Stalled only" filter is active but nothing is stalled.
class _NoStalledItems extends StatelessWidget {
  const _NoStalledItems();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 64, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            l.queueNoStalledTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            l.queueNoStalledBody,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
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
    final l = AppLocalizations.of(context);
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
              label: Text(l.commonRetry),
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
        tween: Tween(
          begin: 0.5,
          end: 1.2,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
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
    final l = AppLocalizations.of(context);
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
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
                            ? l.queueOverlayPoints(
                                widget.points.toStringAsFixed(1))
                            : l.queueOverlayRework,
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
                            l.queueOverlayNext(widget.nextDepartment!),
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
