import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../domain/repositories/qc_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../viewmodel/qc_viewmodel.dart';
import '../../../shared/widgets/status_badge.dart';

/// QC Queue — shows all active QC steps grouped by QC department.
class QcQueueScreen extends StatelessWidget {
  /// When true the queue opens with the "Rework" filter applied — used by the
  /// dashboard "Rework Queue" deep link (`?filter=rework`).
  final bool initialReworkOnly;

  const QcQueueScreen({super.key, this.initialReworkOnly = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => QcViewModel(
        repository: ctx.read<QcRepository>(),
        ws: ctx.read<WsClient>(),
        reworkOnly: initialReworkOnly,
      )..load(),
      child: const _QcQueueView(),
    );
  }
}

class _QcQueueView extends StatelessWidget {
  const _QcQueueView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                    label: Text(l.commonRetry),
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

class _LoadedView extends StatefulWidget {
  final QcLoaded state;
  const _LoadedView({required this.state});

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Filters the grouped queue down to:
  ///   • items whose backing trailer is currently *at* the QC station (we
  ///     always hide upstream `isWaiting` entries — users only want to see
  ///     inspections requiring action);
  ///   • items matching the rework toggle if set;
  ///   • items whose SO number contains the search query (case-insensitive).
  /// Empty departments are dropped so the list doesn't show bare headers.
  Map<String, List<QcQueueItem>> _filteredQueue() {
    final reworkOnly = widget.state.reworkOnly;
    final query = _query.trim().toLowerCase();
    final out = <String, List<QcQueueItem>>{};
    widget.state.groupedQueue.forEach((dept, items) {
      var filtered = items.where((i) => !i.isWaiting).toList();
      if (reworkOnly) {
        filtered = filtered.where((i) => i.isRework).toList();
      }
      if (query.isNotEmpty) {
        filtered = filtered
            .where((i) => i.soNumber.toLowerCase().contains(query))
            .toList();
      }
      if (filtered.isNotEmpty) out[dept] = filtered;
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final visibleQueue = _filteredQueue();
    final totalCount =
        visibleQueue.values.fold<int>(0, (sum, list) => sum + list.length);
    final hasQuery = _query.trim().isNotEmpty;

    // Sort department codes in order: QC_1, QC_2, ..., QC_5, FINAL_QC
    final sortedKeys = visibleQueue.keys.toList()
      ..sort((a, b) {
        const order = ['QC_1', 'QC_2', 'QC_3', 'QC_4', 'QC_5', 'FINAL_QC'];
        final ai = order.indexOf(a);
        final bi = order.indexOf(b);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    return Column(
      children: [
        // Summary header + rework filter — always visible so a deep-linked
        // filter can be cleared even when it leaves the list empty.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.navy.withValues(alpha: 0.05),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist, size: 20, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.qcReadyToInspect(totalCount),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  FilterChip(
                    label: Text(l.qcFilterRework),
                    avatar: const Icon(Icons.replay, size: 16),
                    selected: widget.state.reworkOnly,
                    selectedColor: AppColors.warning.withValues(alpha: 0.2),
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) =>
                        context.read<QcViewModel>().setReworkOnly(v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // SO search bar — operators don't want to scroll through
              // hundreds of trailers when they know the SO number.
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.qcSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: hasQuery
                      ? IconButton(
                          tooltip: l.commonClear,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
        // Grouped list (or empty state)
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => context.read<QcViewModel>().refresh(),
            child: visibleQueue.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              hasQuery
                                  ? Icons.search_off
                                  : Icons.check_circle_outline,
                              size: 64,
                              color: hasQuery
                                  ? Colors.grey
                                  : AppColors.success,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              hasQuery
                                  ? l.qcSearchNoMatchTitle
                                  : widget.state.reworkOnly
                                      ? l.qcNoReworkTitle
                                      : l.qcNoInspectionsTitle,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hasQuery
                                  ? l.qcSearchNoMatchBody(_query.trim())
                                  : widget.state.reworkOnly
                                      ? l.qcNoReworkBody
                                      : l.qcAllInspectedBody,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: sortedKeys.length,
                    itemBuilder: (context, index) {
                      final deptCode = sortedKeys[index];
                      final items = visibleQueue[deptCode]!;
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
    final l = AppLocalizations.of(context);
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
                '${l.qcReadyCount(activeCount)}'
                '${waitingCount > 0 ? ' ${l.qcUpcomingCount(waitingCount)}' : ''}',
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
    final l = AppLocalizations.of(context);
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
                        l.qcEarlierStageFallback;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(
                          l.qcStillAtStage(
                              item.soNumber, stage, item.departmentCode),
                        ),
                      ),
                    );
                  }
                : () async {
                    // Push (not go) so we can await the inspection form and
                    // refresh the queue on return — the trailer just QC'd is
                    // then dropped from the list without a manual pull-to-
                    // refresh.
                    await context.push(
                      '/qc/inspect/${item.stepId}',
                      extra: item,
                    );
                    if (context.mounted) {
                      context.read<QcViewModel>().refresh();
                    }
                  },
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
                                // SO + stage chip + status/rework badges.
                                // Wrap (not Row) so chips re-flow to the next
                                // line on narrow screens instead of overflowing.
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      item.soNumber,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navy,
                                      ),
                                    ),
                                    _StageChip(code: item.departmentCode),
                                    if (isWaiting) const _WaitingChip(),
                                    if (item.isRework)
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
                                              l.trailerDetailReworkBadge(
                                                  item.reworkCount),
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
                                ),
                                const SizedBox(height: 4),
                                // Model + customer
                                Text(
                                  [item.modelName, item.customerName]
                                      .where((s) => s != null && s.isNotEmpty)
                                      .join(' • '),
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey.shade600),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (isWaiting && item.currentStageCode != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    l.qcCurrentlyAt(item.currentStageName ??
                                        item.currentStageCode!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade700,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Trailing column keeps the series badge stacked
                          // above the chevron so neither steals horizontal
                          // room from the title row.
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (item.series != null)
                                SeriesBadge(series: item.series!),
                              if (item.series != null)
                                const SizedBox(height: 6),
                              Icon(
                                isWaiting ? Icons.schedule : Icons.chevron_right,
                                color: Colors.grey,
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
  const _WaitingChip();

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
            AppLocalizations.of(context).qcUpcomingChip,
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
